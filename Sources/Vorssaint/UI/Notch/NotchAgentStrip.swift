// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The closed island while an agent works: its mark on one side of the
/// camera, one reading the person chose on the other. The wings are as wide
/// as the reading, and both sit at the ends, where the island shows.
struct NotchAgentStrip: View {
    @ObservedObject var service: NotchService
    /// Where the island draws it: its own strip as of the last update, or
    /// another display's when the island shows on every display.
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var usage = AgentUsageService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchAgentsReadout) private var readout = NotchAgentReadout.elapsed.rawValue
    @AppStorage(DefaultsKey.notchAgentsLimitDisplay) private var display = NotchAgentLimitDisplay.remaining.rawValue
    @AppStorage(DefaultsKey.notchAgentsLimitFocus) private var focus = NotchAgentLimitFocus.mostUsed.rawValue

    private func working(_ live: [AgentLiveSession]) -> [AgentProvider] {
        AgentProvider.allCases.filter { provider in live.contains { $0.provider == provider } }
    }

    var body: some View {
        // The last agent stopping empties the list before the strip has left.
        NotchStripHold(usage.snapshot.live, shows: !usage.snapshot.live.isEmpty) { strip(live: $0) }
    }

    @ViewBuilder private func strip(live: [AgentLiveSession]) -> some View {
        // Resolve layout once per presentation update. The timeline captures
        // these values, so ticking the clock never remeasures the island or
        // walks the preferences for every font, inset and frame.
        let geometry = displayGeometry ?? service.compactActivityGeometry
        let working = working(live)
        let tint = working.first?.tint ?? .white
        let budget = geometry.compactActivityContentHeight - NotchLayout.compactEdgeGap * 2
        let iconSize = min(working.count > 1 ? 11.0 : 14.0, max(8, budget - 4))
        let lineCount = NotchAgentSupport.stripLines(reading(at: Date(), live: live)).count
        let textSize = NotchAgentSupport.stripLineSize(height: geometry.compactActivityContentHeight, lines: lineCount)
        let iconInset = !geometry.compactActivityUsesFooter
            ? geometry.compactActivityEdgeInset(boxHeight: iconSize + 4, radius: (iconSize + 4) / 2) : 0
        let textInset = !geometry.compactActivityUsesFooter
            ? geometry.compactActivityEdgeInset(boxHeight: NotchAgentSupport.stripTextBox(size: textSize, lines: lineCount), radius: 0) : 0
        HStack(spacing: 0) {
            Button { service.openActivity(.agents) } label: {
                HStack(spacing: 1) {
                    if geometry.compactActivityWingWidth >= 28 {
                        ForEach(working) { NotchAgentGlyph(provider: $0, size: iconSize) }
                    }
                }
                .padding(.leading, iconInset)
                .frame(width: geometry.compactActivityWingWidth, height: geometry.compactActivityContentHeight,
                       alignment: .leading)
                .contentShape(Rectangle())
            }
            Color.clear.frame(width: geometry.compactActivityCameraGap)
            Button { service.openActivity(.agents) } label: {
                Group {
                    if geometry.compactActivityWingWidth >= 42 {
                        NotchAgentReadoutTimeline(readout: NotchAgentReadout(rawValue: readout) ?? .elapsed) { date in
                            let text = reading(at: date, live: live)
                            let lines = NotchAgentSupport.stripLines(text)
                            let size = NotchAgentSupport.stripLineSize(height: geometry.compactActivityContentHeight,
                                                                       lines: lines.count)
                            NotchAgentGauge(lines: lines, limit: lines.count > 1 ? limit(at: date, live: live) : nil,
                                            showsUsed: display == NotchAgentLimitDisplay.used.rawValue, size: size, tint: tint)
                                // A reading that gains a digit, like an hour
                                // passing, needs wider wings; the service
                                // measures the same reading.
                                .onChange(of: NotchAgentSupport.readingShape(text)) { _, _ in
                                    DispatchQueue.main.async { service.refreshPresentation() }
                                }
                        }
                    }
                }
                .padding(.trailing, textInset)
                .frame(width: geometry.compactActivityWingWidth, height: geometry.compactActivityContentHeight,
                       alignment: .trailing)
                .contentShape(Rectangle())
            }
        }
        .frame(height: geometry.compactActivityContentHeight)
        .padding(.horizontal, geometry.compactActivityHorizontalPadding)
        .padding(.top, geometry.compactActivityTopPadding)
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(working.map(\.displayName).joined(separator: ", "))
        .accessibilityValue(reading(at: Date(), live: live))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { service.openActivity(.agents) }
        .accessibilityHint(FeatureStrings.notch(l10n.language).open)
    }

    private func limit(at now: Date, live: [AgentLiveSession]) -> (provider: AgentProvider, window: AgentLimitWindow)? {
        var snapshot = usage.snapshot
        snapshot.live = live
        return NotchAgentSupport.stripLimit(snapshot, focus: NotchAgentLimitFocus(rawValue: focus) ?? .mostUsed, now: now)
    }

    private func reading(at now: Date, live: [AgentLiveSession]) -> String {
        var snapshot = usage.snapshot
        snapshot.live = live
        return NotchAgentSupport.stripReading(snapshot, readout: NotchAgentReadout(rawValue: readout) ?? .elapsed,
                                              display: NotchAgentLimitDisplay(rawValue: display) ?? .remaining,
                                              focus: NotchAgentLimitFocus(rawValue: focus) ?? .mostUsed, now: now)
    }
}

/// Keep the original one-second cadence for time-dependent readings, but
/// install no clock at all for values updated by the observed usage snapshot.
struct NotchAgentReadoutTimeline<Content: View>: View {
    let readout: NotchAgentReadout
    @ViewBuilder var content: (Date) -> Content

    var body: some View {
        if readout.advancesWithClock {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                content(context.date)
            }
        } else {
            content(.now)
        }
    }
}

/// The resting island's wings: the chosen allowance, by default the one
/// closest to running out, as a ring and a number, or today's API value when
/// no allowance is known.
struct NotchAgentRestingWing: View {
    let leading: Bool
    @ObservedObject private var usage = AgentUsageService.shared
    @AppStorage(DefaultsKey.notchAgentsLimitDisplay) private var display = NotchAgentLimitDisplay.remaining.rawValue
    @AppStorage(DefaultsKey.notchAgentsLimitFocus) private var focus = NotchAgentLimitFocus.mostUsed.rawValue

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(now: context.date)
        }
    }

    @ViewBuilder private func content(now: Date) -> some View {
        let snapshot = usage.snapshot
        let limit = NotchAgentSupport.restingLimit(snapshot, focus: NotchAgentLimitFocus(rawValue: focus) ?? .mostUsed, now: now)
        let used = display == NotchAgentLimitDisplay.used.rawValue
        if let limit {
            let tint = agentLimitTint(limit.provider, usedFraction: limit.window.usedFraction)
            if leading {
                NotchAgentRing(value: used ? limit.window.usedFraction : limit.window.remainingFraction,
                               tint: tint, lineWidth: 2)
                    .frame(width: 11, height: 11)
            } else {
                Text(AgentFormat.percent(used ? limit.window.usedFraction : limit.window.remainingFraction))
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
            }
        } else if let provider = AgentProvider.allCases.first(where: snapshot.seen.contains) {
            if leading {
                NotchAgentMark(provider: provider, size: 10)
            } else {
                Text(AgentFormat.cost(snapshot.usage(.today).total.cost))
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}

/// A reading as the closed island draws it. An allowance stacks its share
/// over the time until it renews, beside a ring of the same share; any
/// other reading is a single line.
struct NotchAgentGauge: View {
    let lines: [String]
    let limit: (provider: AgentProvider, window: AgentLimitWindow)?
    let showsUsed: Bool
    let size: CGFloat
    let tint: Color

    var body: some View {
        let gaugeTint = limit.map { agentLimitTint($0.provider, usedFraction: $0.window.usedFraction) } ?? tint
        HStack(spacing: NotchAgentSupport.stripGaugeSpacing) {
            if let limit {
                NotchAgentRing(value: showsUsed ? limit.window.usedFraction : limit.window.remainingFraction,
                               tint: gaugeTint, lineWidth: 2)
                    .frame(width: NotchAgentSupport.stripGaugeRing, height: NotchAgentSupport.stripGaugeRing)
            }
            if lines.count > 1 {
                // Numbers right-aligned in one column, units left-aligned in
                // the next, each column in its own size.
                Grid(alignment: .leading, horizontalSpacing: NotchAgentSupport.stripUnitSpacing,
                     verticalSpacing: NotchAgentSupport.stripLineSpacing) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        let part = NotchAgentSupport.stripParts(line)
                        GridRow(alignment: .firstTextBaseline) {
                            Group {
                                if part.full {
                                    // A lock in two digits' width: the allowance is spent.
                                    Text(part.number).hidden().overlay {
                                        Image(systemName: "lock.fill")
                                            .font(.system(size: NotchAgentSupport.stripNumberSize(size) * 0.85, weight: .bold))
                                    }
                                    .accessibilityLabel(AgentFormat.percent(1))
                                } else {
                                    Text(part.number)
                                }
                            }
                            .font(.system(size: NotchAgentSupport.stripNumberSize(size), weight: .bold))
                            .gridColumnAlignment(.trailing)
                            // Monospaced, so % and h take the same width.
                            Text(part.unit)
                                .font(.system(size: NotchAgentSupport.stripUnitSize(size), weight: .bold, design: .monospaced))
                                .gridColumnAlignment(.leading)
                        }
                        .monospacedDigit()
                        .lineLimit(1)
                        .foregroundStyle(index > 0 ? AnyShapeStyle(.white.opacity(0.55)) : AnyShapeStyle(gaugeTint))
                    }
                }
            } else {
                Text(lines.first ?? "")
                    .font(.system(size: size, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(gaugeTint)
            }
        }
    }
}

/// The notched island at rest with an allowance, as the system's own
/// compact activities read: a mark on the left of the camera, the value on
/// the right. The ring of the share is the mark, and the share stacks over
/// the time until it renews in the same type as a working agent's gauge,
/// whose own mark is the agent's. Without an allowance it rests as before.
struct NotchAgentRestingGauge: View {
    let leading: Bool
    let height: CGFloat
    @ObservedObject private var usage = AgentUsageService.shared
    @AppStorage(DefaultsKey.notchAgentsLimitDisplay) private var display = NotchAgentLimitDisplay.remaining.rawValue
    @AppStorage(DefaultsKey.notchAgentsLimitFocus) private var focus = NotchAgentLimitFocus.mostUsed.rawValue

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(now: context.date)
        }
    }

    @ViewBuilder private func content(now: Date) -> some View {
        let showsUsed = display == NotchAgentLimitDisplay.used.rawValue
        if let limit = NotchAgentSupport.restingLimit(usage.snapshot, focus: NotchAgentLimitFocus(rawValue: focus) ?? .mostUsed,
                                                      now: now) {
            let lines = NotchAgentSupport.stripLines(NotchAgentSupport.limitReading(
                limit.window, display: showsUsed ? .used : .remaining, now: now))
            let size = NotchAgentSupport.stripLineSize(height: height, lines: lines.count)
            let tint = agentLimitTint(limit.provider, usedFraction: limit.window.usedFraction)
            if leading {
                NotchAgentRing(value: showsUsed ? limit.window.usedFraction : limit.window.remainingFraction,
                               tint: tint, lineWidth: 2.2)
                    .frame(width: NotchAgentSupport.restingGaugeRing, height: NotchAgentSupport.restingGaugeRing)
            } else {
                NotchAgentGauge(lines: lines, limit: nil, showsUsed: showsUsed, size: size, tint: tint)
            }
        } else {
            NotchAgentRestingWing(leading: leading)
        }
    }
}

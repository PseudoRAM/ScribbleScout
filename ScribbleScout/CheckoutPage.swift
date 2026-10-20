import SwiftUI
import UIKit

/// The reference page uses the same coordinate space for ink, handwriting, and linked cards.
enum NotebookTheme {
    static let paper = UIColor(red: 0.987, green: 0.981, blue: 0.969, alpha: 1)
    static let ink = Color(red: 0.12, green: 0.13, blue: 0.18)
    static let burgundy = Color(red: 0.51, green: 0.12, blue: 0.24)
    static let sage = Color(red: 0.34, green: 0.42, blue: 0.32)
    static let muted = Color(red: 0.35, green: 0.36, blue: 0.40)
}

enum CheckoutPaper {
    static let transcript = """
    Subscription checkout. Simple for new users. Supports multiple plans, monthly or annual. Handle trial to paid conversion. Good analytics and revenue reporting. Minimize engineering overhead.
    Stripe checkout? Stripe hosted versus custom? Need flexible billing. Tax, coupons, metered usage? Can we support enterprise later?
    What did we decide last time? Looked at Stripe Checkout. Discussed custom flow for more control. Concerned about flexibility, promos and trials. Need to revisit with billing team.
    What should I ask the team?
    Proposed flow: Member signs up and selects a plan. Checkout handles payment, collects billing information, and applies discounts. Subscription is active, managed in the account, and supports renewal or cancellation.
    """
    static func draw(in context: CGContext) {
        let ink = UIColor(NotebookTheme.ink)
        let wine = UIColor(NotebookTheme.burgundy)
        let sage = UIColor(NotebookTheme.sage)

        func text(_ value: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat = 31) {
            let font = UIFont(name: "Caveat-Regular", size: size) ?? UIFont(name: "Noteworthy-Light", size: size)!
            (value as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [
                .font: font, .foregroundColor: ink, .kern: -0.15,
                .strokeColor: NotebookTheme.paper, .strokeWidth: -2.5
            ])
        }
        func line(_ points: [CGPoint], color: UIColor = UIColor(NotebookTheme.ink), width: CGFloat = 1.6) {
            guard let first = points.first else { return }
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(width)
            context.setLineCap(.round)
            context.move(to: first)
            for point in points.dropFirst() { context.addLine(to: point) }
            context.strokePath()
        }
        func bullets(_ values: [String], x: CGFloat, y: CGFloat, step: CGFloat = 41, size: CGFloat = 31) {
            for (index, value) in values.enumerated() {
                let top = y + CGFloat(index) * step
                ink.setFill()
                context.fillEllipse(in: CGRect(x: x + 3, y: top + 23, width: 4, height: 5))
                text(value, x + 29, top, size)
            }
        }
        func underline(_ x: CGFloat, _ y: CGFloat, _ end: CGFloat, color: UIColor = UIColor(NotebookTheme.ink)) {
            let path = UIBezierPath()
            path.move(to: CGPoint(x: x, y: y))
            path.addQuadCurve(to: CGPoint(x: end, y: y - 9), controlPoint: CGPoint(x: (x + end) / 2, y: y - 15))
            path.lineWidth = 1.8
            color.setStroke()
            path.stroke()
        }
        func connector(from start: CGPoint, to end: CGPoint, color: UIColor) {
            let path = UIBezierPath()
            path.move(to: start)
            path.addCurve(to: end, controlPoint1: CGPoint(x: start.x + 40, y: start.y - 3),
                          controlPoint2: CGPoint(x: end.x - 42, y: end.y + 6))
            color.withAlphaComponent(0.65).setStroke()
            path.lineWidth = 1.2
            path.stroke()
            color.withAlphaComponent(0.45).setFill()
            context.fillEllipse(in: CGRect(x: start.x - 10, y: start.y - 10, width: 20, height: 20))
            color.setFill()
            context.fillEllipse(in: CGRect(x: start.x - 6.5, y: start.y - 6.5, width: 13, height: 13))
        }

        text("Subscription  checkout", 60, 34, 44)
        underline(60, 100, 389)
        bullets([
            "Simple for new users",
            "Supports multiple plans (monthly / annual)",
            "Handle trial → paid conversion",
            "Good analytics & revenue reporting",
            "Minimize engineering overhead"
        ], x: 61, y: 110)

        text("Stripe  checkout?", 655, 75, 36)
        let oval = UIBezierPath()
        oval.move(to: CGPoint(x: 897, y: 92))
        oval.addCurve(to: CGPoint(x: 620, y: 122), controlPoint1: CGPoint(x: 887, y: 26), controlPoint2: CGPoint(x: 602, y: 64))
        oval.addCurve(to: CGPoint(x: 897, y: 92), controlPoint1: CGPoint(x: 610, y: 172), controlPoint2: CGPoint(x: 895, y: 135))
        wine.setStroke(); oval.lineWidth = 1.25; oval.stroke()
        let secondArc = UIBezierPath()
        secondArc.move(to: CGPoint(x: 674, y: 72))
        secondArc.addCurve(to: CGPoint(x: 852, y: 73), controlPoint1: CGPoint(x: 723, y: 61), controlPoint2: CGPoint(x: 823, y: 62))
        secondArc.lineWidth = 1; secondArc.stroke()
        connector(from: CGPoint(x: 897, y: 92), to: CGPoint(x: 984, y: 59), color: wine)
        bullets([
            "Stripe hosted vs custom?",
            "Need flexible billing",
            "Tax, coupons, metered usage?",
            "Can we support enterprise later?"
        ], x: 583, y: 151, step: 43)

        text("What did we decide last time?", 48, 363, 41)
        underline(52, 430, 458)
        bullets([
            "Looked at Stripe Checkout",
            "Discussed custom flow for more control",
            "Concerned about flexibility (promos, trials)",
            "Need to revisit with billing team"
        ], x: 51, y: 442, step: 42)
        connector(from: CGPoint(x: 489, y: 396), to: CGPoint(x: 584, y: 424), color: sage)

        text("What should I ask the team?", 968, 391, 40)
        underline(975, 455, 1350, color: wine)

        text("Proposed flow", 54, 652, 40)
        underline(55, 713, 239)
        func box(_ title: String, rect: CGRect, labelX: CGFloat) {
            let path = UIBezierPath()
            path.move(to: CGPoint(x: rect.minX + 17, y: rect.minY + 4))
            path.addCurve(to: CGPoint(x: rect.maxX - 17, y: rect.minY),
                          controlPoint1: CGPoint(x: rect.midX - 20, y: rect.minY - 4), controlPoint2: CGPoint(x: rect.maxX - 27, y: rect.minY - 4))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - 12), controlPoint: CGPoint(x: rect.maxX + 7, y: rect.minY + 1))
            path.addQuadCurve(to: CGPoint(x: rect.minX + 12, y: rect.maxY), controlPoint: CGPoint(x: rect.maxX + 5, y: rect.maxY + 3))
            path.addCurve(to: CGPoint(x: rect.minX + 17, y: rect.minY + 4),
                          controlPoint1: CGPoint(x: rect.minX - 7, y: rect.maxY), controlPoint2: CGPoint(x: rect.minX - 2, y: rect.minY + 18))
            path.lineWidth = 1.4; ink.setStroke(); path.stroke()
            text(title, labelX, rect.minY + 10, 33)
        }
        box("Member", rect: CGRect(x: 77, y: 730, width: 145, height: 62), labelX: 109)
        box("Checkout", rect: CGRect(x: 321, y: 721, width: 184, height: 70), labelX: 358)
        box("Subscription", rect: CGRect(x: 593, y: 721, width: 191, height: 65), labelX: 632)
        line([CGPoint(x: 234, y: 759), CGPoint(x: 306, y: 755)])
        line([CGPoint(x: 298, y: 748), CGPoint(x: 307, y: 755), CGPoint(x: 299, y: 764)])
        line([CGPoint(x: 515, y: 752), CGPoint(x: 580, y: 752)])
        line([CGPoint(x: 572, y: 744), CGPoint(x: 581, y: 752), CGPoint(x: 573, y: 761)])
        bullets(["signs up", "selects plan"], x: 80, y: 801, step: 35)
        bullets(["handles payment", "collects billing info", "applies discounts"], x: 331, y: 797, step: 33)
        bullets(["active subscription", "manage in account", "renewal / cancellation"], x: 608, y: 800, step: 33)
    }
}

enum ContextAction: String, Identifiable {
    case explain = "Explain", research = "Research", recall = "Recall", followUp = "Follow up", original = "Past meeting · 13 Oct"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .explain: "doc.text"
        case .research: "magnifyingglass"
        case .recall, .original: "clock"
        case .followUp: "bubble"
        }
    }
    var detail: String {
        switch self {
        case .explain:
            "Hosted Checkout is the quickest route to launch. A custom integration gives the team more control over pricing, trials, and complex billing. A hybrid approach lets you start hosted and keep a path open for enterprise needs."
        case .research:
            "Compare Stripe’s hosted Checkout with a custom integration, with trade-offs for flexibility, compliance and long-term scale."
        case .recall, .original:
            "We proposed a custom flow, but did not record a final decision.\n\n• Looked at Stripe Checkout\n• Discussed custom flow for more control\n• Concerned about flexibility (promos, trials)\n• Need to revisit with billing team"
        case .followUp:
            "What should I ask the team?\n\n• Which pricing and trial rules do we need at launch?\n• Do we need metered usage or custom coupons?\n• What will enterprise customers need?\n• Can we start hosted and move to custom later?"
        }
    }
}

struct CheckoutAnnotations: View {
    @ObservedObject var session: NoteSession
    var onAction: (ContextAction) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            researchCard.frame(width: 416, height: 292).offset(x: 984, y: 34)
            recallCard.frame(width: 321, height: 153).offset(x: 584, y: 400)
            contextBar.frame(width: 380, height: 54).offset(x: 1020, y: 475)
            aiNote.frame(width: 486, height: 283).offset(x: 914, y: 590)
        }
        .font(.system(size: 18))
        .foregroundStyle(NotebookTheme.ink)
        .frame(width: 1448, height: 1026, alignment: .topLeading)
    }

    private var researchCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "globe").font(.system(size: 20))
                Text("Research · Web").font(.system(size: 16))
                Spacer()
                Menu {
                    Button("Copy summary", systemImage: "doc.on.doc") { UIPasteboard.general.string = ContextAction.research.detail }
                    Button("Read research", systemImage: "doc.text.magnifyingglass") { onAction(.research) }
                } label: { Image(systemName: "ellipsis").frame(width: 32, height: 32) }
                .accessibilityLabel("Research options")
            }
            .foregroundStyle(NotebookTheme.burgundy)
            .padding(.top, 9).padding(.bottom, 9)
            Text("Which checkout option matches\nour billing flow?")
                .font(.system(size: 21, weight: .semibold)).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Text("Compare Stripe’s hosted Checkout with a custom integration, with trade-offs for flexibility, compliance and long-term scale.")
                .foregroundStyle(NotebookTheme.muted).lineSpacing(3)
                .padding(.top, 10).fixedSize(horizontal: false, vertical: true)
            Link(destination: URL(string: "https://docs.stripe.com/payments/checkout")!) {
                Text("Stripe Docs ↗").underline().foregroundStyle(NotebookTheme.burgundy)
            }.padding(.top, 13)
            Spacer(minLength: 8)
            Rectangle().fill(NotebookTheme.burgundy.opacity(0.13)).frame(height: 1)
            HStack(spacing: 0) {
                Button {
                    session.edit { $0.keptResearch = !($0.keptResearch ?? false) }
                } label: {
                    Label(session.note.keptResearch == true ? "Kept in notes" : "Keep in notes",
                          systemImage: session.note.keptResearch == true ? "bookmark.fill" : "bookmark")
                        .frame(maxWidth: .infinity, minHeight: 51)
                }
                Rectangle().fill(NotebookTheme.burgundy.opacity(0.14)).frame(width: 1, height: 28)
                Button { onAction(.followUp) } label: {
                    Label("Follow up", systemImage: "bubble").frame(maxWidth: .infinity, minHeight: 51)
                }
            }
            .font(.system(size: 16)).foregroundStyle(NotebookTheme.burgundy)
        }
        .padding(.horizontal, 24)
        .background(Color(red: 0.991, green: 0.972, blue: 0.976), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(NotebookTheme.burgundy.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.07), radius: 5, y: 3)
    }

    private var recallCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                Image(systemName: "doc.text").font(.system(size: 21))
                Text("Past meeting · 13 Oct").font(.system(size: 16))
                Spacer(minLength: 0)
                Menu {
                    Button("Open past meeting", systemImage: "doc.text") { onAction(.original) }
                    Button("Copy summary", systemImage: "doc.on.doc") { UIPasteboard.general.string = ContextAction.recall.detail }
                } label: { Image(systemName: "ellipsis").frame(width: 24, height: 24) }
                .accessibilityLabel("Past meeting options")
            }.foregroundStyle(NotebookTheme.sage)
            Text("We proposed a custom flow, but did not record a final decision.")
                .font(.system(size: 17.5)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            Button { onAction(.original) } label: {
                Text("Jump to original ↗").underline().foregroundStyle(NotebookTheme.sage)
            }
            .frame(minHeight: 25, alignment: .leading)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.976, green: 0.978, blue: 0.968), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(NotebookTheme.sage.opacity(0.45), lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 3)
    }

    private var contextBar: some View {
        HStack(spacing: 0) {
            ForEach([ContextAction.explain, .research, .recall]) { action in
                if action != .explain { Rectangle().fill(.black.opacity(0.07)).frame(width: 1, height: 28) }
                Button { onAction(action) } label: {
                    Label(action.rawValue, systemImage: action.symbol)
                        .font(.system(size: 15, weight: .medium))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.black.opacity(0.07), lineWidth: 1))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2)
                .fill(.white).frame(width: 15, height: 15).rotationEffect(.degrees(45)).offset(y: -7)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.11), radius: 9, y: 4)
    }

    private var aiNote: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("AI note").underline().font(.system(size: 16))
            } icon: { Image(systemName: "sparkles").font(.system(size: 20)) }
                .foregroundStyle(NotebookTheme.burgundy)
            Text("Key trade-offs for our use case").font(.system(size: 18, weight: .semibold))
            VStack(alignment: .leading, spacing: 6) {
                aiBullet("Hosted Checkout: fastest to launch, lower maintenance, solid for standard flows.")
                aiBullet("Custom integration: more flexibility for custom pricing, trials and complex billing logic.")
                aiBullet("Given our need for flexible billing and future enterprise support, a hybrid approach may work well (start with hosted, plan for custom later).")
            }
            .font(.system(size: 17)).foregroundStyle(NotebookTheme.muted)
        }
        .padding(.horizontal, 28).padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.991, green: 0.978, blue: 0.976).opacity(0.7), in: RoundedRectangle(cornerRadius: 21))
        .overlay(RoundedRectangle(cornerRadius: 21).stroke(NotebookTheme.burgundy.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [6, 6])))
    }

    private func aiBullet(_ value: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("•")
            Text(value).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
        }
    }
}

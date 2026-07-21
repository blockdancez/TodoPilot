import SwiftUI

struct StatusIslandPreview: View {
    @EnvironmentObject private var environment: AppEnvironment
    @ObservedObject var taskStore: TaskStore

    var body: some View {
        HStack(spacing: 10) {
            PixelPlaneMark(color: .white)
                .frame(width: 36, height: 16)

            Text(taskStore.nextAction?.shortTitle ?? "TodoPilot")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 180, alignment: .leading)

            Text("\(taskStore.activeTasks.count)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.black)
                .frame(minWidth: 20, minHeight: 20)
                .background(Color.white, in: Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(red: 0.02, green: 0.02, blue: 0.025), in: Capsule())
        .overlay(
            Capsule()
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
    }
}

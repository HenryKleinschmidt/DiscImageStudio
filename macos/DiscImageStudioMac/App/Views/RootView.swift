import DiscImageStudioKit
import SwiftUI

struct RootView: View {
    @ObservedObject var model: WorkspaceViewModel

    var body: some View {
        ZStack {
            Theme.pageBackground.ignoresSafeArea()
            if model.hasProject {
                ProjectWorkspaceView(model: model)
                    .transition(.opacity)
            } else {
                HomeView(model: model)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: model.hasProject)
        .sheet(isPresented: $model.isNewProjectPresented) {
            NewProjectView(model: model, initialFamily: model.newProjectFamily)
        }
        .sheet(isPresented: $model.isProjectSettingsPresented) {
            ProjectSettingsView(model: model)
        }
        .sheet(isPresented: $model.isAboutPresented) {
            AboutView()
        }
        .onOpenURL { url in
            model.openProject(at: url)
        }
        .alert(item: $model.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}

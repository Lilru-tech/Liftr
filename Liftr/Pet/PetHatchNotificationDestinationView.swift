import SwiftUI

struct PetHatchNotificationDestinationView: View {
    @StateObject private var viewModel = PetDetailViewModel()

    var body: some View {
        PetDetailView(viewModel: viewModel)
            .task {
                await viewModel.load()
                viewModel.startPollingIfNeeded()
                PetHatchEventHandler.handleHatchEvent(navigateToProfile: false)
            }
    }
}

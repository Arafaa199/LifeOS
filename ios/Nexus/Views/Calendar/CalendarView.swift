import SwiftUI

struct CalendarView: View {
    @StateObject private var viewModel = CalendarViewModel()
    @State private var selectedSegment = 0

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("", selection: $selectedSegment) {
                    Text("Today").tag(0)
                    Text("Week").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 12)

                TabView(selection: $selectedSegment) {
                    CalendarTodayView(viewModel: viewModel)
                        .tag(0)

                    CalendarWeekView(viewModel: viewModel)
                        .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.large)
        }
        .task {
            await viewModel.loadData()
        }
        .onChange(of: selectedSegment) { newValue in
            Task {
                if newValue == 0 {
                    await viewModel.fetchTodayEvents()
                } else if newValue == 1 {
                    await viewModel.fetchWeekEvents()
                }
            }
        }
    }
}

#Preview {
    CalendarView()
}

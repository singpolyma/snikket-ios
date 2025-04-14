import SwiftUI

struct WelcomeView: View {
    let accounts: AccountsModel
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                VStack(spacing: 24) {
                    VStack {
                        Spacer()
                        Image(systemName: "person.3.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 100, height: 100)
                            .foregroundColor(.blue)
                        Spacer()
                    }
                    .frame(height: geometry.size.height / 3)

                    Text("Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Spacer()
                    
                    VStack(spacing: 16) {
                        Button("Scan an Invite") {
                            // Handle scan action
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(25)

                        NavigationLink(destination: LoginView(accounts: accounts)) {
                            Text("Use Existing Account")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.gray.opacity(0.2))
                                .foregroundColor(.blue)
                                .cornerRadius(25)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding()
            }
        }
    }
}

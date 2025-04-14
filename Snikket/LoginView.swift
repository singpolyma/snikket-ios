import SwiftUI

struct LoginView: View {
    let accounts: AccountsModel
    @State var accountSet: Bool = false
    @State var accountId = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var triedPassword = false
    @State private var authFailed = false
    @State private var isLoading = false
    
    @FocusState private var focusedField: Field?
    enum Field {
        case passwordText
        case passwordSecure
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Welcome Back")
                .font(.largeTitle)
                .bold()
            
            TextField("Jabber ID", text: $accountId)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                .foregroundColor(.gray)
                .disabled(accountSet)
            
            ZStack {
                Group {
                    if isPasswordVisible {
                        // Regular TextField for visible password
                        TextField("Password", text: $password)
                            .focused($focusedField, equals: .passwordText)
                    } else {
                        // SecureField for hidden password
                        SecureField("Password", text: $password)
                            .focused($focusedField, equals: .passwordSecure)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                .textContentType(.password)
                .autocapitalization(.none)
                .autocorrectionDisabled(true)
                .onSubmit {
                    accounts.setupClient(accountId)
                }
                
                HStack {
                    Spacer()
                    // Eye button for toggling password visibility
                    Button(action: {
                        isPasswordVisible.toggle() // Toggle password visibility
                        focusedField = isPasswordVisible ? .passwordText : .passwordSecure
                    }) {
                        Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                            .foregroundColor(.gray)
                            .padding(.trailing, 10)
                    }
                    .padding(.top, 8)
                }
            }
            
            if authFailed {
                Text("Authentication failed. Please try again.")
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.top, 4)
            }
            
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    .scaleEffect(1)
                    .padding()
            } else {
                Button("Log In") {
                    isLoading = true
                    accountSet = true
                    accounts.setupClient(accountId)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(25)
            }
            
            Spacer()
        }
        .padding()
        .onAppear {
            accounts.needPassword = { client in
                if triedPassword {
                    password = ""
                    authFailed = true
                    isLoading = false
                } else {
                    triedPassword = true
                    authFailed = false
                    client.usePassword(password: password)
                }
            }
        }
        .onDisappear {
            accounts.needPassword = nil
        }
    }
}

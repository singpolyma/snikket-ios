import SwiftUI
import Snikket
import ExyteChat
import UserNotifications

@main
struct SnikketApp: App {
    private let mediaStore: Snikket.MediaStoreFS
    private let persistence: Snikket.Sqlite
    @ObservedObject private var accounts: AccountsModel
    private let notificationDelegate: NotificationDelegate
    
    var body: some Scene {
        WindowGroup {
            if accounts.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    .scaleEffect(5)
                    .padding()
            } else if (accounts.authenticating != nil) {
                LoginView(accounts: accounts, accountSet: true, accountId: accounts.authenticating!)
            } else if (accounts.client != nil && accounts.chats != nil && accounts.needPassword == nil) {
                ContentView(client: accounts.client!, chats: accounts.chats!)
            } else {
                WelcomeView(accounts: accounts)
            }
        }
    }
    
    init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Error requesting notification permission: \(error)")
            }
        }
        
        Snikket.setup { errPtr in
            if let err = errPtr {
                print(String(cString: err))
            }
            exit(1)
        }
        let supportURL = URL.applicationSupportDirectory.appending(path: "Snikket")
        let supportPath = supportURL.path()
        if !FileManager.default.fileExists(atPath: supportPath) {
            _ = try? FileManager.default.createDirectory(atPath: supportPath, withIntermediateDirectories: true, attributes: nil)
        }
        let dbpath = supportURL.appending(path: "snikket.sqlite3").path()
        let cachePath = URL.cachesDirectory.appending(path: "Snikket").path()
        if !FileManager.default.fileExists(atPath: cachePath) {
            _ = try? FileManager.default.createDirectory(atPath: cachePath, withIntermediateDirectories: true, attributes: nil)
        }
        mediaStore = Snikket.MediaStoreFS(path: cachePath)
        persistence = Snikket.Sqlite(dbfile: dbpath, media: mediaStore)
        let accounts = AccountsModel(persistence: persistence, mediaStore: mediaStore)
        self.accounts = accounts
        
        notificationDelegate = NotificationDelegate(accounts: accounts)
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }
}

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    var accounts: AccountsModel

    init(accounts: AccountsModel) {
        self.accounts = accounts
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                 didReceive response: UNNotificationResponse,
                                 withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        if let needsPassword = userInfo["needsPassword"] as? String {
            DispatchQueue.main.async {
                self.accounts.authenticating = needsPassword
            }
        }
        completionHandler()
    }
}

class AccountsModel: ObservableObject {
    @Published private(set) var client: Snikket.Client? = nil
    @Published var authenticating: String? = nil
    @Published private(set) var chats: ChatsModel? = nil
    private let persistence: Snikket.Sqlite
    private let mediaStore: Snikket.MediaStoreFS
    @Published var isLoading = true
    @Published var needPassword: ((Snikket.Client)->Void)? = nil
    
    init(persistence: Snikket.Sqlite, mediaStore: Snikket.MediaStoreFS) {
        self.persistence = persistence
        self.mediaStore = mediaStore
        persistence.listAccounts { accounts in
            DispatchQueue.main.async {
                if !accounts.isEmpty {
                    self.setupClient(accounts[0])
                }
                self.isLoading = false
            }
        }
    }
    
    @MainActor
    func setupClient(_ accountId: String) {
        client = Snikket.Client(address: accountId, persistence: persistence)
        chats = ChatsModel(client: client!, mediaStore: mediaStore)
        client!.addPasswordNeededListener { client in
            let accountId = client.accountId()
            DispatchQueue.main.async {
                if let needPassword = self.needPassword {
                    needPassword(client)
                } else {
                    let content = UNMutableNotificationContent()
                    content.title = "Authentication Required"
                    content.body = "Tap to enter password"
                    content.sound = .default
                    content.userInfo = ["needsPassword": accountId]

                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
                    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)

                    UNUserNotificationCenter.current().add(request)
                }
            }
        }
        client!.addStatusOnlineListener {
            let authDone = self.authenticating == self.client?.accountId()
            DispatchQueue.main.async {
                self.needPassword = nil
                if authDone {
                    self.authenticating = nil
                }
            }
        }
        client!.start()
    }
}

struct Chat: Identifiable {
    let id: String
    let chat: Snikket.Chat
}

class ChatViewModel: ObservableObject {
    var messageData: [String: Snikket.ChatMessage] = [:]
    @Published var messages: [Message] = []
    @ObservedObject var chats: ChatsModel
    private var _chat: Snikket.Chat?
    var chat: Snikket.Chat? {
        get { _chat }
        set {
            _chat = newValue
            messages = []
            messageData = [:]
            loadMessages()
        }
    }
    var name: String { chat?.getDisplayName() ?? "" }
    
    init(chat: Snikket.Chat?, chats: ChatsModel) {
        self.chats = chats
        _chat = chat
    }
    
    static func mapStatus(_ status: Snikket.MessageStatus) -> Message.Status {
        switch status {
        case .MessagePending: .sending
        case .MessageDeliveredToServer: .sent
        case .MessageDeliveredToDevice: .sent
        case .MessageFailedToSend: .sending // .error(draft)
        }
    }
    
    func messageUser(_ message: Snikket.ChatMessage) -> User {
        //print("SWIFT", message.localId, message.senderId)
        let participant = self.chat!.getParticipantDetails(participantId: message.senderId)
        return User(id: message.senderId, name: participant.displayName, avatarURL: participant.photoUri.flatMap { self.chats.avatars[$0] }, isCurrentUser: participant.isSelf)
    }
    
    func mkMessage(_ message: Snikket.ChatMessage) -> Message {
        messageData[message.serverId ?? message.localId ?? UUID().uuidString] = message
        return Message(
            id: message.serverId ?? message.localId ?? UUID().uuidString,
            user: messageUser(message),
            status: Self.mapStatus(message.status),
            createdAt: parseDate(date: message.timestamp)!,
            text: message.text == nil ? "" : message.html(),
            attachments: message.attachments.map { Attachment(id: $0.hashes.first?.toUri() ?? UUID().uuidString, url: URL(string: $0.uris[0])!, type: $0.mime.hasPrefix("video/") ? .video : .image) },
            replyMessage: message.replyToMessage.map { replyTo in
                self.mkMessage(replyTo).toReplyMessage()
            }
        )
    }
    
    func loadMessages() {
        chat?.getMessagesBefore(beforeId: nil, beforeTime: nil) { messages in
            let newMessages = messages.map { message in
                self.mkMessage(message)
            }
            DispatchQueue.main.async {
                self.messages = newMessages
            }
        }
    }
    
    func loadMessagesBefore(message: Message) {
        chat?.getMessagesBefore(beforeId: message.id, beforeTime: message.createdAt.ISO8601Format()) { messages in
            var toPrepend: [Message] = []
            var updates: [Int: Message] = [:]
            
            messages.reversed().forEach() { message in
                if let index = self.messages.firstIndex(where: { m in
                    m.id == (message.serverId ?? message.localId)
                }) {
                    updates[index] = self.mkMessage(message)
                } else {
                    toPrepend.insert(self.mkMessage(message), at: 0)
                }
            }
            DispatchQueue.main.async {
                updates.forEach { (key: Int, value: Message) in
                    self.messages[key] = value
                }
                self.messages.insert(contentsOf: toPrepend, at: 0)
            }
        }
    }
}

class ChatsModel: ObservableObject {
    private let mediaStore: Snikket.MediaStoreFS
    @Published var avatars: [String: URL] = [:]
    @Published var chats: [Chat] = []
    @Published var selectedChat: ChatViewModel? = nil
    init(client: Snikket.Client, mediaStore: Snikket.MediaStoreFS) {
        self.mediaStore = mediaStore
        self.selectedChat = ChatViewModel(chat: nil, chats: self)
        client.addChatsUpdatedListener { chats in
            chats.forEach { chat in
                if let avatarUri = chat.getPhoto() {
                    self.loadAvatar(uri: avatarUri)
                }
            }
            let newChats = client.getChats().map { Chat(id: $0.chatId, chat: $0) }
            DispatchQueue.main.async {
                self.chats = newChats
            }
        }
        client.addChatMessageListener { message, eventType in
            if message.chatId() == self.selectedChat?.chat?.chatId {
                let msg = self.selectedChat!.mkMessage(message)
                if let index = self.selectedChat!.messages.firstIndex(where: { m in
                    m.id == message.serverId || m.id == message.localId
                }) {
                    DispatchQueue.main.async {
                        self.selectedChat!.messages[index] = msg
                    }
                } else {
                    DispatchQueue.main.async {
                        self.selectedChat!.messages.append(msg)
                    }
                }
            }
        }
    }
    
    func loadAvatar(uri: String) {
        if avatars[uri] != nil {
            return
        }
        mediaStore.getMediaPath(uri: uri) { maybePath in
            if let path = maybePath {
                DispatchQueue.main.async {
                    self.avatars[uri] = URL(fileURLWithPath: path)
                }
            }
        }
    }
}

import SwiftUI
import Snikket
import ExyteChat
import SVGView
import UniformTypeIdentifiers
import ZMarkupParser

func parseDate(date: String) -> Date? {
    let frac = DateFormatter()
    frac.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
    
    let nofrac = DateFormatter()
    nofrac.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
    
    return frac.date(from: date) ?? nofrac.date(from: date)
}

struct ContentView: View {
    let client: Snikket.Client
    @ObservedObject var chats: ChatsModel
    var selectedChatId: Binding<String?> {
        Binding(
            get: { chats.selectedChat!.chat?.chatId },
            set: { newValue in
                chats.selectedChat!.chat = chats.chats.first(where: { $0.id == newValue })?.chat
            }
        )
    }
    
    var body: some View {
        NavigationSplitView {
            List(chats.chats, selection: selectedChatId) { chat in
                NavigationLink(value: chat.id) {
                    HStack {
                        let avatarURL = chat.chat.getPhoto().flatMap { chats.avatars[$0] }
                        CachedAsyncImage(url: avatarURL) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            SVGView(string: String(chat.chat.getPlaceholder().removingPercentEncoding!.dropFirst(19)))
                        }
                            .frame(width: 50, height: 50)
                            .clipShape(Circle())
                        
                        VStack(alignment: .leading) {
                            Text(chat.chat.getDisplayName())
                                .font(.headline)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(chat.chat.preview())
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .padding(.horizontal, 5)
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Chats")
        } detail: {
            AnyView(ChatDetailView(client: client, viewModel: chats.selectedChat!))
        }
    }
}

struct ChatDetailView: View {
    let client: Snikket.Client
    @StateObject var viewModel: ChatViewModel
    
    var body: some View {
        ChatView(messages: viewModel.messages) { toSend in
            Task {
                let builder = if let replyTo = toSend.replyMessage, let replyToMessage = viewModel.messageData[replyTo.id] {
                    replyToMessage.reply()
                } else {
                    Snikket.ChatMessageBuilder()
                }
                builder.localId = toSend.id ?? UUID().uuidString
                builder.text = toSend.text
                if let giphy = toSend.giphyMedia {
                    builder.addAttachment(attachment: ChatAttachment.create(name: giphy.title, mime: giphy.isVideo ? "video/mp4" : "image/webp", size: -1, uri: (giphy.isVideo ? giphy.video?.videoAssets?.large?.url : giphy.images?.original?.webPUrl) ?? giphy.url) )
                }
                for media in toSend.medias {
                    if let url = await media.getURL() {
                        if let attachment = await withCheckedContinuation({ next in
                            client.prepareAttachment(source: AttachmentSource(path: url.path(), mime: UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"), callback: { attachment in next.resume(returning: attachment) } )
                        }) {
                            builder.addAttachment(attachment: attachment)
                        }
                    }
                }
                if let recording = toSend.recording, let url = recording.url {
                    if let attachment = await withCheckedContinuation({ next in
                        client.prepareAttachment(source: AttachmentSource(path: url.path(), mime: "audio/aac"), callback: { attachment in next.resume(returning: attachment) } )
                    }) {
                        builder.addAttachment(attachment: attachment)
                    }
                }
                self.viewModel.chat!.sendMessage(message: builder)
            }
        } messageMenuAction: { (selectedMenuAction: DefaultMessageMenuAction, defaultActionClosure, message) in
            switch selectedMenuAction {
            case .edit:
                defaultActionClosure(message, .edit { editedText in
                    DispatchQueue.main.async {
                        if let localId = viewModel.messageData[message.id]?.localId {
                            let builder = Snikket.ChatMessageBuilder()
                            builder.localId = UUID().uuidString
                            builder.text = editedText
                            viewModel.chat!.correctMessage(localId: localId, message: builder)
                        }
                    }
                })
            default:
                defaultActionClosure(message, selectedMenuAction)
            }
        }
        .messageUseStyler({ html in
            return AttributedString(ZHTMLParserBuilder.initWithDefault()
                .set(rootStyle: MarkupStyle(font: MarkupStyleFont(size: 14)))
                .add(BLOCKQUOTE_HTMLTagName(), withCustomStyle: MarkupStyle(backgroundColor: MarkupStyleColor(name: MarkupStyleColorName.lightgray)))
                .build().render(html.hasPrefix("<div>") ? String(html.dropFirst(5)) : html))
        })
        .enableLoadMore(pageSize: 10, { before in
            viewModel.loadMessagesBefore(message: before)
        })
        .giphyConfig(GiphyConfiguration(
            giphyKey: Bundle.main.object(forInfoDictionaryKey: "GIPHY_KEY") as? String,
            showAttributionMark: true
        ))
        .navigationTitle(viewModel.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack {
                    let avatarURL = viewModel.chat?.getPhoto().flatMap { viewModel.chats.avatars[$0] }
                    CachedAsyncImage(url: avatarURL) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        if let chat = viewModel.chat {
                            SVGView(string: String(chat.getPlaceholder().removingPercentEncoding!.dropFirst(19)))
                        }
                    }
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                    Text(viewModel.name)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }
}

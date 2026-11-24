import SwiftUI

@main struct LGRemoteApp: App {
    var body: some Scene { WindowGroup { ContentView().preferredColorScheme(.dark) } }
}

struct ContentView: View {
    @StateObject private var remote = Remote()
    @State private var settings = false
    @State private var keyboard = false
    @State private var appList = false
    @State private var numbers = false
    @State private var typed = ""
    @State private var last = CGSize.zero
    @State private var moved = false
    private let panel = Color(red: 0.13, green: 0.15, blue: 0.20)
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "tv").font(.title)
                    VStack(alignment: .leading) { Text("LG Remote").font(.title2.bold()); Text(remote.status).font(.caption).foregroundStyle(remote.ready ? Color.green : Color.gray) }
                    Spacer(); button("gearshape", "Настройки") { settings = true }
                }
                HStack {
                    button("power", "Выключить", color: .red) { remote.request("system/turnOff") }.disabled(!remote.ready)
                    button("power.circle", "Включить") { remote.wake() }
                    Spacer()
                    Button(remote.ready ? "Отключить" : "Подключить") { if remote.ready { remote.disconnect() } else if remote.host.isEmpty { settings = true } else { remote.connect() } }.buttonStyle(.borderedProminent).tint(.indigo)
                }
                VStack(spacing: 14) {
                    HStack(spacing: 8) {
                        VStack { button("plus", "Громче") { remote.request("audio/volumeUp") }; Text("VOL").font(.caption2); button("minus", "Тише") { remote.request("audio/volumeDown") } }
                        Spacer(minLength: 0)
                        VStack(spacing: 7) {
                            nav("chevron.up", "UP")
                            HStack(spacing: 6) { nav("chevron.left", "LEFT"); Button { remote.key("ENTER") } label: { Text("OK").font(.headline).frame(width: 62, height: 62).background(.indigo, in: Circle()) }; nav("chevron.right", "RIGHT") }
                            nav("chevron.down", "DOWN")
                        }.disabled(!remote.pointerReady)
                        Spacer(minLength: 0)
                        VStack { button("chevron.up", "Следующий канал") { remote.request("tv/channelUp") }; Text("CH").font(.caption2); button("chevron.down", "Предыдущий канал") { remote.request("tv/channelDown") } }
                    }
                    HStack { button("arrow.uturn.backward", "Назад") { remote.key("BACK") }; Spacer(); button("house", "Домой") { remote.key("HOME") }; Spacer(); button("speaker.slash", "Без звука") { remote.key("MUTE") }; Spacer(); button("rectangle.portrait.and.arrow.right", "Входы") { remote.key("INPUT") } }.disabled(!remote.pointerReady)
                    RoundedRectangle(cornerRadius: 22).fill(panel).frame(height: 155).overlay {
                        VStack(spacing: 7) { Image(systemName: "cursorarrow.motionlines").font(.largeTitle); Text("Сенсорная панель").font(.subheadline); Text("Проведи пальцем или нажми").font(.caption2) }.foregroundStyle(.secondary)
                    }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        if abs(value.translation.width) + abs(value.translation.height) > 4 { moved = true }
                        if moved { remote.move(Int((value.translation.width-last.width)*1.6), Int((value.translation.height-last.height)*1.6)); last = value.translation }
                    }.onEnded { _ in if !moved { remote.click() }; moved = false; last = .zero }).disabled(!remote.pointerReady)
                    HStack { button("backward.fill", "Перемотка") { remote.key("REWIND") }; Spacer(); button("play.fill", "Воспроизвести") { remote.key("PLAY") }; Spacer(); button("pause.fill", "Пауза") { remote.key("PAUSE") }; Spacer(); button("forward.fill", "Вперёд") { remote.key("FASTFORWARD") } }.disabled(!remote.pointerReady)
                    HStack { button("keyboard", "Клавиатура") { keyboard = true }; Spacer(); button("number", "Цифры") { numbers = true }; Spacer(); button("square.grid.2x2", "Приложения") { appList = true }; Spacer(); button("play.rectangle.fill", "YouTube", color: .red) { remote.launch("youtube.leanback.v4") } }
                    if let lampa = remote.apps.first(where: { $0.title.localizedCaseInsensitiveContains("lampa") || $0.id.localizedCaseInsensitiveContains("lampa") }) { Button("Открыть Lampa") { remote.launch(lampa.id) }.buttonStyle(.borderedProminent).tint(.indigo) }
                }.disabled(!remote.ready)
                Text("Локальное управление • webOS").font(.caption2).foregroundStyle(.secondary)
            }.padding(20)
        }.background(Color(red: 0.055, green: 0.065, blue: 0.09)).foregroundStyle(.white)
        .sheet(isPresented: $settings) { NavigationStack { Form {
            Section("Телевизор") { TextField("IP, например 192.168.1.50", text: $remote.host).keyboardType(.numbersAndPunctuation).autocorrectionDisabled(); TextField("MAC для включения (необязательно)", text: $remote.mac).textInputAutocapitalization(.never).autocorrectionDisabled() }
            Section { Button("Подключиться") { remote.connect(); settings = false }; Button("Удалить ключ сопряжения", role: .destructive) { remote.forget() } }
            Section { Text("iPhone и ТВ должны находиться в одной локальной сети. Разреши подключение на экране телевизора. Для включения активируй LG Connect Apps / Mobile TV On, если доступно.") }
        }.navigationTitle("Настройки").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { settings = false } } } } }
        .sheet(isPresented: $keyboard) { NavigationStack { Form { TextField("Текст для телевизора", text: $typed); Button("Отправить") { remote.text(typed); typed = "" }; Button("Удалить символ") { remote.request("com.webos.service.ime/deleteCharacters", ["count": 1]) }; Button("Enter") { remote.request("com.webos.service.ime/sendEnterKey") } }.navigationTitle("Клавиатура").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { keyboard = false } } } } }
        .sheet(isPresented: $appList) { NavigationStack { List { if remote.apps.isEmpty { Text("Список приложений пока недоступен") }; ForEach(remote.apps) { app in Button(app.title) { remote.launch(app.id); appList = false } } }.navigationTitle("Приложения").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { appList = false } } } } }
        .sheet(isPresented: $numbers) { VStack { Text("Каналы").font(.title2.bold()); LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3)) { ForEach([1,2,3,4,5,6,7,8,9,0], id: \.self) { n in Button { remote.key(String(n)) } label: { Text(String(n)).font(.title).frame(maxWidth: .infinity).frame(height: 65).background(panel, in: RoundedRectangle(cornerRadius: 15)) } } }; Button("Готово") { numbers = false } }.padding(24).presentationDetents([.medium, .large]) }
    }
    private func nav(_ icon: String, _ key: String) -> some View { button(icon, key) { remote.key(key) } }
    private func button(_ icon: String, _ label: String, color: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 19, weight: .semibold)).foregroundStyle(color).frame(width: 46, height: 48).background(panel, in: RoundedRectangle(cornerRadius: 15)) }.buttonStyle(.plain).accessibilityLabel(label)
    }
}

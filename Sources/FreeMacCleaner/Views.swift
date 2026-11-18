import SwiftUI
import AppKit
import Combine

@main
struct FreeMacCleanerApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup("Free Mac Cleaner") {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 960, minHeight: 600)
        }
        Settings {
            SettingsView()
                .environmentObject(state)
                .frame(width: 560, height: 420)
        }
    }
}

// MARK: - Janela principal

struct ContentView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationSplitView {
            List(selection: $state.selection) {
                DiskHeader()
                    .listRowSeparator(.hidden)
                    .padding(.vertical, 6)

                NavigationLink(value: Page.home) { Label("Início", systemImage: "house") }
                sectionRow(.overview)

                SwiftUI.Section("Discos") {
                    ForEach(state.volumes) { v in
                        NavigationLink(value: Page.volume(v.id)) {
                            HStack {
                                Label(v.name, systemImage: v.symbol).lineLimit(1)
                                Spacer()
                                Text("\(Fmt.size(v.free)) livres")
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                SwiftUI.Section("Limpeza") {
                    ForEach(Section.cleanup) { s in sectionRow(s) }
                    sectionRow(.disks)
                }
                SwiftUI.Section("iCloud") {
                    sectionRow(.icloud)
                }
                SwiftUI.Section("Ferramentas") {
                    sectionRow(.videos)
                }
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 290)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button {
                        state.scanEverything()
                    } label: {
                        Label("Escanear tudo", systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(!state.scanning.isEmpty)
                    DonateButton(prominent: true)
                        .controlSize(.large)
                }
                .padding()
            }
        } detail: {
            switch state.selection {
            case .home, nil:
                HomeView()
            case .section(.overview):
                OverviewView()
            case .section(.videos):
                VideosView()
            case .section(let s):
                SectionView(section: s).id(s)
            case .volume(let path):
                if let v = state.volumes.first(where: { $0.id == path }) {
                    VolumeView(volume: v).id(path)
                } else {
                    ContentUnavailableView("Disco desconectado", systemImage: "externaldrive.badge.questionmark")
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { state.goBack() } label: { Image(systemName: "chevron.left") }
                    .help("Voltar")
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(state.backStack.isEmpty)
                Button { state.goForward() } label: { Image(systemName: "chevron.right") }
                    .help("Avançar")
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(state.forwardStack.isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                let all = state.pageAllSelected()
                Button {
                    state.selectPage(!all)
                } label: {
                    Label(all ? "Desmarcar tudo" : "Selecionar tudo",
                          systemImage: all ? "checkmark.circle.fill" : "checkmark.circle")
                        .labelStyle(.titleAndIcon)
                }
                .help("Marca tudo o que pode ser marcado nesta tela (⌘⇧A)")
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(state.pageSelectable().isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                let sel = state.globalSelected()
                Button {
                    state.confirmingGlobal = true
                } label: {
                    Label("Limpar selecionados (\(Fmt.size(sel.reduce(0) { $0 + $1.item.size })))", systemImage: "sparkles")
                        .labelStyle(.titleAndIcon)
                }
                .help("Manda para a Lixeira o que está no disco e remove o download do que está no iCloud, em todas as categorias")
                .disabled(sel.isEmpty || state.busy)
            }
        }
        .globalCleanConfirmation()
        .sheet(isPresented: $state.showingDonate) { DonateView().environmentObject(state) }
        .onReceive(NotificationCenter.default.publisher(for: NSWorkspace.didMountNotification, object: nil).merge(
            with: NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification),
                  NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification))) { _ in
            state.refreshVolumes()
        }
        .alert("Concluído", isPresented: Binding(get: { state.lastMessage != nil }, set: { if !$0 { state.lastMessage = nil } })) {
            Button("OK") { state.lastMessage = nil }
        } message: {
            Text(state.lastMessage ?? "")
        }
    }

    @ViewBuilder private func sectionRow(_ s: Section) -> some View {
        NavigationLink(value: Page.section(s)) {
            HStack {
                Label(s.title, systemImage: s.symbol)
                Spacer()
                if s == .overview {
                    if Section.global.contains(where: { state.results[$0] != nil }) {
                        Text(Fmt.size(Section.global.reduce(0) { $0 + state.total($1) }))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                } else if state.scanning.contains(s) {
                    ProgressView().controlSize(.small)
                } else if state.results[s] != nil {
                    Text(Fmt.size(state.total(s)))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Início

struct HomeView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        let found = Section.global.reduce(Int64(0)) { $0 + state.total($1) }
        let scannedAny = Section.global.contains { state.results[$0] != nil }
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Free Mac Cleaner").font(.largeTitle.bold())
                        Text(scannedAny ? "Dá para liberar até \(Fmt.size(found))." : "Escaneie para ver quanto espaço dá para liberar.")
                            .font(.title3).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        DonateButton()
                        Button { state.scanEverything() } label: {
                            Label("Escanear tudo", systemImage: "magnifyingglass").frame(minWidth: 160)
                        }
                        .controlSize(.large).buttonStyle(.borderedProminent).tint(.green)
                        .disabled(!state.scanning.isEmpty)
                        if scannedAny {
                            Button { state.selection = .section(.overview) } label: {
                                Label("Revisar e limpar", systemImage: "square.stack.3d.up").frame(minWidth: 160)
                            }
                            .controlSize(.large)
                        }
                    }
                }

                if !state.scanning.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Escaneando: " + state.scanning.map(\.title).sorted().joined(separator: ", "))
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Discos").font(.title2.bold())
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                    ForEach(state.volumes) { v in
                        Button { state.selection = .volume(v.id) } label: { VolumeCard(volume: v) }
                            .buttonStyle(.plain)
                    }
                }

                Text("Categorias").font(.title2.bold())
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                    ForEach(Section.cleanup + [.disks, .icloud, .videos]) { s in
                        Button { state.selection = .section(s) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Image(systemName: s.symbol).font(.title2).foregroundStyle(s == .icloud ? .blue : .green)
                                Text(s.title).font(.headline).lineLimit(1)
                                Group {
                                    if state.scanning.contains(s) {
                                        Text("Escaneando…")
                                    } else if state.results[s] != nil {
                                        Text("\(state.results[s]?.count ?? 0) itens · \(Fmt.size(state.total(s)))")
                                    } else {
                                        Text("Não escaneado")
                                    }
                                }
                                .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(24)
        }
    }
}

struct VolumeCard: View {
    let volume: VolumeInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: volume.symbol).font(.title2)
                VStack(alignment: .leading, spacing: 0) {
                    Text(volume.name).font(.headline).lineLimit(1)
                    Text(volume.format).font(.caption).foregroundStyle(.secondary)
                }
            }
            ProgressView(value: volume.fraction)
                .tint(volume.fraction > 0.9 ? .red : (volume.fraction > 0.75 ? .orange : .green))
            Text("\(Fmt.size(volume.free)) livres de \(Fmt.size(volume.total))")
                .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
    }
}

// MARK: - Disco

struct VolumeView: View {
    @EnvironmentObject private var state: AppState
    let volume: VolumeInfo

    private var section: Section { volume.isRoot ? .temp : .disks }

    var body: some View {
        let items = state.items(on: volume)
        let selected = items.filter { $0.selected && $0.blockedReason == nil }
        let selectedSize = selected.reduce(Int64(0)) { $0 + $1.size }

        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                VolumeCard(volume: volume)
                HStack {
                    Text(volume.isRoot
                         ? "Arquivos temporários do seu usuário neste SSD. As outras categorias da barra lateral também liberam espaço aqui."
                         : "Arquivos temporários, downloads incompletos, \"._\" órfãos e a lixeira deste disco.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        state.scan(section)
                    } label: {
                        Label(state.results[section] == nil ? "Procurar temporários" : "Procurar de novo", systemImage: "magnifyingglass")
                    }
                    .disabled(state.scanning.contains(section))
                    Button {
                        state.videoFolder = volume.isRoot ? Scanner.home.path : volume.url.path
                        state.selection = .section(.videos)
                        state.scan(.videos)
                    } label: { Label("Comprimir vídeos", systemImage: "film.stack") }
                    if !volume.isRoot {
                        Button {
                            NSWorkspace.shared.open(volume.url)
                        } label: { Label("Abrir", systemImage: "folder") }
                    }
                }
            }
            .padding()

            Divider()

            if state.scanning.contains(section) {
                ProgressView("Procurando…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if state.results[section] == nil {
                ContentUnavailableView("Ainda não escaneado", systemImage: volume.symbol,
                                       description: Text("Clique em Procurar temporários."))
            } else if items.isEmpty {
                ContentUnavailableView("Nenhum temporário", systemImage: "checkmark.circle",
                                       description: Text("Este disco está limpo."))
            } else {
                ItemTable(section: section, items: items)
            }

            Divider()

            HStack {
                Button("Selecionar todos") { setAll(items, true) }
                Button("Desmarcar") { setAll(items, false) }
                Spacer()
                Text("\(selected.count) selecionados · \(Fmt.size(selectedSize))")
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                Button {
                    state.confirmingVolume = true
                } label: {
                    Text("Limpar este disco").frame(minWidth: 180)
                }
                .buttonStyle(.borderedProminent).tint(.green)
                .disabled(selected.isEmpty || state.busy)
            }
            .padding()
        }
        .confirmationDialog("Limpar \(selected.count) itens (\(Fmt.size(selectedSize))) de \(volume.name)?",
                            isPresented: $state.confirmingVolume, titleVisibility: .visible) {
            Button("Limpar") { state.perform(section, only: selected) }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(volume.isRoot ? "Os itens vão para a Lixeira." : "O que já está na lixeira do disco é apagado de vez; o resto vai para a Lixeira.")
        }
        .onAppear {
            if state.results[section] == nil { state.scan(section) }
        }
    }

    private func setAll(_ items: [ScanItem], _ value: Bool) {
        for i in items where i.blockedReason == nil { state.setSelected(i.id, in: section, value) }
    }
}

struct DiskHeader: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        let used = max(0, state.disk.total - state.disk.free)
        let fraction = state.disk.total > 0 ? Double(used) / Double(state.disk.total) : 0
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if let icon = NSImage(named: "AppIcon") ?? NSApp.applicationIconImage {
                    Image(nsImage: icon).resizable().frame(width: 36, height: 36)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("Free Mac Cleaner").font(.headline)
                    Text("\(Fmt.size(state.disk.free)) livres de \(Fmt.size(state.disk.total))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            ProgressView(value: fraction)
                .tint(fraction > 0.9 ? .red : (fraction > 0.75 ? .orange : .green))
        }
    }
}

// MARK: - Seção

struct SectionView: View {
    @EnvironmentObject private var state: AppState
    let section: Section

    var body: some View {
        let items = state.visibleItems(section)
        let selected = state.selectedVisible(section)
        let selectedSize = selected.reduce(Int64(0)) { $0 + $1.size }

        VStack(alignment: .leading, spacing: 0) {
            // Cabeçalho
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(section.title, systemImage: section.symbol).font(.title2.bold())
                    Spacer()
                    Button {
                        state.scan(section)
                    } label: {
                        Label(state.results[section] == nil ? "Escanear" : "Escanear de novo", systemImage: "arrow.clockwise")
                    }
                    .disabled(state.scanning.contains(section))
                }
                Text(section.explanation).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

                if section == .largeFiles {
                    Stepper("Mostrar arquivos a partir de \(state.largeFileMinMB) MB", value: $state.largeFileMinMB, in: 50...10_000, step: 50)
                }
                if section == .oldFiles {
                    HStack(spacing: 24) {
                        Stepper("Sem abrir há mais de \(state.oldFilesMinDays) dias", value: $state.oldFilesMinDays, in: 30...1825, step: 30)
                        Stepper("A partir de \(state.oldFilesMinMB) MB", value: $state.oldFilesMinMB, in: 1...5000, step: 5)
                    }
                }
                if section == .downloads {
                    Stepper("Sem abrir há mais de \(state.downloadsMinDays) dias", value: $state.downloadsMinDays, in: 7...730, step: 7)
                }
                if section == .icloud { ICloudFilters() }

                if state.permissionDenied.contains(section) {
                    PermissionBanner()
                }
            }
            .padding()

            Divider()

            // Lista
            if state.scanning.contains(section) {
                VStack(spacing: 10) {
                    ProgressView()
                    if section == .icloud {
                        Text("\(state.progressCount) itens verificados…").foregroundStyle(.secondary)
                    } else {
                        Text("Escaneando…").foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if state.results[section] == nil {
                ContentUnavailableView("Ainda não escaneado", systemImage: section.symbol,
                                       description: Text("Clique em Escanear para ver o que dá para liberar."))
            } else if items.isEmpty {
                ContentUnavailableView("Nada encontrado", systemImage: "checkmark.circle",
                                       description: Text("Nenhum item com esses critérios."))
            } else {
                ItemTable(section: section, items: items)
            }

            Divider()

            // Rodapé
            HStack {
                Button("Selecionar todos") { state.selectAllVisible(section, true) }
                Button("Desmarcar") { state.selectAllVisible(section, false) }
                Spacer()
                Text("\(selected.count) selecionados · \(Fmt.size(selectedSize))")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button(role: section == .trash ? .destructive : nil) {
                    state.confirming = section
                } label: {
                    Text(actionTitle).frame(minWidth: 180)
                }
                .buttonStyle(.borderedProminent)
                .tint(section == .trash ? .red : .green)
                .disabled(selected.isEmpty || state.busy)
            }
            .padding()
        }
        .confirmationDialog(confirmTitle(selected.count, selectedSize), isPresented: Binding(get: { state.confirming == section }, set: { if !$0 { state.confirming = nil } }), titleVisibility: .visible) {
            Button(actionTitle, role: section == .trash ? .destructive : nil) { state.perform(section) }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(confirmMessage)
        }
        .onAppear {
            if state.results[section] == nil && section != .icloud && section != .largeFiles {
                state.scan(section)
            }
        }
    }

    private var actionTitle: String {
        switch section {
        case .icloud: "Remover downloads"
        case .trash: "Apagar de vez"
        default: "Mover para a Lixeira"
        }
    }

    private func confirmTitle(_ n: Int, _ size: Int64) -> String {
        "\(actionTitle): \(n) itens (\(Fmt.size(size)))?"
    }

    private var confirmMessage: String {
        switch section {
        case .icloud: "Os arquivos continuam no iCloud e nos seus outros aparelhos. Só a cópia deste Mac sai do disco; eles baixam de novo quando você abrir."
        case .trash: "Isso não pode ser desfeito."
        default: "Os itens vão para a Lixeira. Dá para recuperar pelo Finder até você esvaziá-la."
        }
    }
}

struct ICloudFilters: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                Picker("Tipo", selection: $state.icloudKind) {
                    ForEach(FileKind.allCases) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 260)
                Picker("Tamanho mínimo", selection: $state.icloudMinMB) {
                    Text("100 KB").tag(0.1)
                    Text("1 MB").tag(1.0)
                    Text("10 MB").tag(10.0)
                    Text("100 MB").tag(100.0)
                    Text("1 GB").tag(1000.0)
                }
                .frame(width: 220)
                Picker("Sem abrir há", selection: $state.icloudMinDays) {
                    Text("Qualquer tempo").tag(0)
                    Text("30 dias").tag(30)
                    Text("90 dias").tag(90)
                    Text("6 meses").tag(180)
                    Text("1 ano").tag(365)
                }
                .frame(width: 220)
            }
            HStack {
                TextField("Buscar por nome ou pasta", text: $state.icloudSearch)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                Spacer()
                SettingsLink {
                    Label("Pastas protegidas (\(state.protectedFolders.count))", systemImage: "lock.shield")
                }
            }
            if state.results[.icloud] != nil {
                Text("\(state.icloudSkippedProjects.count) pastas de projeto com código foram puladas · \(state.icloudAlreadyInCloud) arquivos já estão só na nuvem")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct PermissionBanner: View {
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("O macOS bloqueou parte desta pasta. Dê Acesso Total ao Disco ao app para ver tudo.")
            Spacer()
            Button("Abrir Ajustes") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
            }
        }
        .padding(10)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Tabela

struct ItemTable: View {
    @EnvironmentObject private var state: AppState
    let section: Section
    let items: [ScanItem]

    var body: some View {
        Table(items) {
            TableColumn("") { item in
                Toggle("", isOn: Binding(
                    get: { item.selected },
                    set: { state.setSelected(item.id, in: section, $0) }))
                .labelsHidden()
                .disabled(item.blockedReason != nil)
            }
            .width(24)

            TableColumn("Nome") { item in
                HStack(spacing: 6) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                        .resizable().frame(width: 16, height: 16)
                    Text(item.name).lineLimit(1).truncationMode(.middle)
                }
                .help(item.url.path)
            }
            .width(min: 180, ideal: 260)

            TableColumn("Pasta") { item in
                Text(item.parentPath).lineLimit(1).truncationMode(.head).foregroundStyle(.secondary)
            }

            TableColumn("Tamanho") { item in
                Text(Fmt.size(item.size)).monospacedDigit()
            }
            .width(90)

            TableColumn("Último acesso") { item in
                Text(item.lastAccess.map { Fmt.date.string(from: $0) } ?? "—").foregroundStyle(.secondary)
            }
            .width(110)

            if section == .disks {
                TableColumn("O que acontece") { item in
                    if item.inVolumeTrash {
                        Label("Apagar de vez", systemImage: "trash.slash").foregroundStyle(.red)
                    } else {
                        Label("Lixeira", systemImage: "trash").foregroundStyle(.green)
                    }
                }
                .width(130)
            }
            if section == .icloud {
                TableColumn("Situação") { item in
                    if let why = item.blockedReason {
                        Label(why, systemImage: "exclamationmark.icloud").foregroundStyle(.orange)
                    } else {
                        Label("Seguro na nuvem", systemImage: "checkmark.icloud").foregroundStyle(.green)
                    }
                }
                .width(170)
            }
        }
        .contextMenu(forSelectionType: ScanItem.ID.self) { ids in
            Button("Mostrar no Finder") {
                let urls = items.filter { ids.contains($0.id) }.map(\.url)
                NSWorkspace.shared.activateFileViewerSelecting(urls)
            }
        }
    }
}

// MARK: - Ajustes

struct SettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Form {
            SwiftUI.Section {
                Toggle("Proteger pastas de projetos com código", isOn: $state.protectProjects)
                Text("Pula pastas com .git, Package.swift, .xcodeproj, project.godot, package.json e afins.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            SwiftUI.Section("Pastas protegidas do iCloud") {
                if state.protectedFolders.isEmpty {
                    Text("Nenhuma").foregroundStyle(.secondary)
                }
                ForEach(state.protectedFolders, id: \.self) { path in
                    HStack {
                        Image(systemName: "lock.fill").foregroundStyle(.green)
                        Text(path.replacingOccurrences(of: Scanner.mobileDocuments.path + "/com~apple~CloudDocs", with: "iCloud Drive"))
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button(role: .destructive) {
                            state.protectedFolders.removeAll { $0 == path }
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                    }
                }
                Button("Adicionar pasta…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = true
                    panel.directoryURL = Scanner.mobileDocuments.appendingPathComponent("com~apple~CloudDocs")
                    if panel.runModal() == .OK {
                        for url in panel.urls where !state.protectedFolders.contains(url.path) {
                            state.protectedFolders.append(url.path)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}


// MARK: - Tudo

/// Confirmação da limpeza geral (usada pela barra de ferramentas e pela tela "Tudo").
struct GlobalCleanConfirmation: ViewModifier {
    @EnvironmentObject private var state: AppState

    func body(content: Content) -> some View {
        let rows = state.globalSelected()
        let local = rows.filter { $0.section != .icloud }
        let cloud = rows.filter { $0.section == .icloud }
        let localSize = local.reduce(Int64(0)) { $0 + $1.item.size }
        let cloudSize = cloud.reduce(Int64(0)) { $0 + $1.item.size }
        content.confirmationDialog("Liberar \(Fmt.size(localSize + cloudSize))?",
                                   isPresented: $state.confirmingGlobal, titleVisibility: .visible) {
            Button("Apagar e remover downloads") { state.performGlobal() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("""
            • \(local.count) itens do disco vão para a Lixeira (\(Fmt.size(localSize))). Dá para recuperar pelo Finder.
            • \(cloud.count) arquivos do iCloud terão só o download removido (\(Fmt.size(cloudSize))). Eles continuam na nuvem.
            """)
        }
    }
}

extension View {
    func globalCleanConfirmation() -> some View { modifier(GlobalCleanConfirmation()) }
}

struct OverviewView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        let rows = state.overviewRows()
        let selected = state.globalSelected()
        let selectedSize = selected.reduce(Int64(0)) { $0 + $1.item.size }
        let anyScanning = !state.scanning.isEmpty
        let scannedAny = Section.global.contains { state.results[$0] != nil }

        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Tudo", systemImage: Section.overview.symbol).font(.title2.bold())
                    Spacer()
                    Button { state.scanEverything() } label: {
                        Label(scannedAny ? "Escanear tudo de novo" : "Escanear tudo", systemImage: "arrow.clockwise")
                    }
                    .disabled(anyScanning)
                }
                Text(Section.overview.explanation).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if anyScanning {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Escaneando: " + state.scanning.map(\.title).sorted().joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding()

            Divider()

            if rows.isEmpty {
                if anyScanning {
                    ProgressView("Escaneando…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView(scannedAny ? "Nada encontrado" : "Ainda não escaneado",
                                           systemImage: Section.overview.symbol,
                                           description: Text(scannedAny ? "Nenhum item com os critérios atuais." : "Clique em Escanear tudo."))
                }
            } else {
                Table(rows) {
                    TableColumn("") { row in
                        Toggle("", isOn: Binding(
                            get: { row.item.selected },
                            set: { state.setSelected(row.item.id, in: row.section, $0) }))
                        .labelsHidden()
                        .disabled(row.item.blockedReason != nil)
                    }
                    .width(24)

                    TableColumn("Nome") { row in
                        HStack(spacing: 6) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: row.item.url.path))
                                .resizable().frame(width: 16, height: 16)
                            Text(row.item.name).lineLimit(1).truncationMode(.middle)
                        }
                        .help(row.item.url.path)
                    }
                    .width(min: 180, ideal: 240)

                    TableColumn("Categoria") { row in
                        Label(row.section.title, systemImage: row.section.symbol)
                            .lineLimit(1).foregroundStyle(.secondary)
                    }
                    .width(min: 120, ideal: 170)

                    TableColumn("O que acontece") { row in
                        if let why = row.item.blockedReason {
                            Label(why, systemImage: "exclamationmark.icloud").foregroundStyle(.orange)
                        } else if row.item.inVolumeTrash {
                            Label("Apagar de vez", systemImage: "trash.slash").foregroundStyle(.red)
                        } else if row.section == .icloud {
                            Label("Remover download", systemImage: "icloud.and.arrow.up").foregroundStyle(.blue)
                        } else {
                            Label("Lixeira", systemImage: "trash").foregroundStyle(.green)
                        }
                    }
                    .width(min: 130, ideal: 150)

                    TableColumn("Tamanho") { row in
                        Text(Fmt.size(row.item.size)).monospacedDigit()
                    }
                    .width(90)

                    TableColumn("Pasta") { row in
                        Text(row.item.parentPath).lineLimit(1).truncationMode(.head).foregroundStyle(.secondary)
                    }
                }
                .contextMenu(forSelectionType: UUID.self) { ids in
                    Button("Mostrar no Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting(rows.filter { ids.contains($0.id) }.map(\.item.url))
                    }
                }
            }

            Divider()

            HStack {
                Button("Selecionar todos") { state.selectAllGlobal(true) }
                Button("Desmarcar todos") { state.selectAllGlobal(false) }
                Spacer()
                Text("\(selected.count) selecionados · \(Fmt.size(selectedSize))")
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                Button {
                    state.confirmingGlobal = true
                } label: {
                    Text("Apagar e remover downloads").frame(minWidth: 220)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(selected.isEmpty || state.busy)
            }
            .padding()
        }
    }
}


// MARK: - Vídeos

struct VideosView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        let items = state.visibleItems(.videos)
        let selected = state.selectedVisible(.videos)
        let before = selected.reduce(Int64(0)) { $0 + $1.size }
        let after = selected.reduce(Int64(0)) { $0 + ($1.video?.estimatedSize ?? $1.size) }
        let lossy = selected.filter { $0.video?.mode == .light || $0.video?.mode == .strong }.count
        let limitedHere = items.filter { $0.video?.limited == true }

        VStack(spacing: 0) {
            header(limitedHere: limitedHere)
                .padding()
            Divider()

            content(items: items)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            if state.compressing {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            ProgressView(value: state.compressProgress)
                                .frame(width: 200)
                            Text("Vídeo \(state.compressIndex) de \(state.compressTotal): \(state.compressName) · \(Int(state.compressProgress * 100))%")
                                .lineLimit(1).truncationMode(.middle)
                        }
                        HStack(spacing: 8) {
                            ProgressView(value: Double(state.compressIndex - 1) + state.compressProgress, total: Double(max(state.compressTotal, 1)))
                                .frame(width: 200)
                                .tint(.green)
                            Text("Lote: \(state.compressDone) prontos · \(Fmt.size(state.compressSaved)) economizados")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .font(.callout.monospacedDigit())
                    Spacer(minLength: 8)
                    Button("Cancelar") { state.cancelCompression() }
                }
                .padding(.horizontal).padding(.vertical, 8)
                .background(.green.opacity(0.08))
                Divider()
            }
            footer(selected: selected, before: before, after: after, lossy: lossy)
                .padding(.horizontal).padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog(confirmTitle(selected.count), isPresented: $state.confirmingCompress, titleVisibility: .visible) {
            if state.compressReplace {
                Button("Substituir e apagar cada original assim que ficar pronto", role: .destructive) { state.compressSelected(policy: .replaceAndDelete) }
                Button("Substituir e mandar originais para a Lixeira") { state.compressSelected(policy: .replaceToTrash) }
            } else {
                Button("Comprimir e manter originais") { state.compressSelected(policy: .keepOriginal) }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Economia estimada: \(Fmt.size(before - after)). A resolução é mantida."
                 + (lossy > 0 ? " Atenção: \(lossy) vídeos vão perder um pouco de qualidade (níveis Leve ou Forte)." : "")
                 + (state.compressReplace
                    ? " Cada vídeo comprimido fica com o nome e no lugar do original, que só sai depois da versão nova ser conferida. Na Lixeira dá para recuperar; apagar de vez libera o espaço na hora, mas não tem volta."
                    : " As versões comprimidas ficam ao lado dos originais, com \"(comprimido)\" no nome. Nada é apagado — o espaço só é economizado depois que você apagar os originais."))
        }
    }

    private func confirmTitle(_ n: Int) -> String {
        if let f = state.videoFolderFilter {
            return "Comprimir \(n) vídeos da pasta \(URL(fileURLWithPath: f).lastPathComponent)?"
        }
        return "Comprimir \(n) vídeos?"
    }

    // MARK: Cabeçalho

    @ViewBuilder
    private func header(limitedHere: [ScanItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(Section.videos.title, systemImage: Section.videos.symbol).font(.title2.bold())
                Spacer()
                Button { state.scan(.videos) } label: {
                    Label(state.results[.videos] == nil ? "Procurar vídeos" : "Procurar de novo", systemImage: "magnifyingglass")
                }
                .disabled(state.scanning.contains(.videos) || state.compressing)
            }
            Text(Section.videos.explanation)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Image(systemName: "folder")
                Text(state.videoFolder.map { $0.replacingOccurrences(of: NSHomeDirectory(), with: "~") } ?? "Todos os discos (pasta pessoal e discos externos)")
                    .lineLimit(1).truncationMode(.middle)
                    .layoutPriority(-1)
                Button("Escolher pasta…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    if panel.runModal() == .OK, let url = panel.url {
                        state.videoFolder = url.path
                        state.videoFolderFilter = nil
                        state.scan(.videos)
                    }
                }
                if state.videoFolder != nil {
                    Button("Todos os discos") { state.videoFolder = nil; state.videoFolderFilter = nil; state.scan(.videos) }
                }
                Spacer(minLength: 8)
                Toggle("Modo rápido", isOn: $state.videoFastMode)
                    .toggleStyle(.switch).controlSize(.small)
                    .fixedSize()
                    .disabled(state.compressing)
                    .help("Usa o chip de vídeo do Mac na velocidade máxima: cerca de 35% mais rápido, com o mesmo tamanho final e diferença de qualidade quase invisível.")
                Stepper("A partir de \(state.videoMinMB) MB", value: $state.videoMinMB, in: 20...5000, step: 20)
                    .fixedSize()
            }
            if !limitedHere.isEmpty {
                let modes = Set(limitedHere.compactMap { $0.video?.mode })
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(limitedHere.count == 1 ? "1 vídeo já está compacto e não reduz à metade sem perder qualidade." : "\(limitedHere.count) vídeos já estão compactos e não reduzem à metade sem perder qualidade.")
                        .lineLimit(2)
                        .layoutPriority(-1)
                    Spacer(minLength: 8)
                    Picker("Para eles:", selection: Binding(
                        get: { modes.count == 1 ? modes.first! : CompressMode.skip },
                        set: { state.setLimitedMode($0) })) {
                        Text(CompressMode.skip.title).tag(CompressMode.skip)
                        Text(CompressMode.light.title).tag(CompressMode.light)
                        Text(CompressMode.strong.title).tag(CompressMode.strong)
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                .padding(8)
                .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: Conteúdo

    @ViewBuilder
    private func content(items: [ScanItem]) -> some View {
        if state.scanning.contains(.videos) {
            ProgressView("Analisando vídeos… \(state.progressCount)")
        } else if state.results[.videos] == nil {
            ContentUnavailableView("Escolha onde procurar", systemImage: "film.stack",
                                   description: Text("Escolha uma pasta ou clique em Procurar vídeos para olhar todos os discos."))
        } else if state.results[.videos]?.isEmpty ?? true {
            ContentUnavailableView("Nenhum vídeo grande", systemImage: "checkmark.circle",
                                   description: Text("Nenhum vídeo .mp4, .mov ou .m4v a partir de \(state.videoMinMB) MB."))
        } else {
            HStack(spacing: 0) {
                VideoFolderList()
                    .frame(width: 300)
                    .frame(maxHeight: .infinity)
                Divider()
                videoTable(items)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func videoTable(_ items: [ScanItem]) -> some View {
        Table(items) {
            TableColumn("") { item in
                Toggle("", isOn: Binding(get: { item.selected },
                                         set: { state.setSelected(item.id, in: .videos, $0) }))
                .labelsHidden()
                .disabled(item.blockedReason != nil)
            }
            .width(24)
            TableColumn("Vídeo") { item in
                HStack(spacing: 6) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path)).resizable().frame(width: 16, height: 16)
                    Text(item.name).lineLimit(1).truncationMode(.middle)
                }
                .help(item.url.path)
            }
            .width(min: 160, ideal: 240)
            TableColumn("Resolução") { item in
                Text(item.video?.resolution ?? "—").foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 90, ideal: 130)
            TableColumn("Formato") { item in
                Text(item.video.map { $0.codec + ($0.hdr ? " HDR" : "") } ?? "—").foregroundStyle(.secondary)
            }
            .width(min: 50, ideal: 70)
            TableColumn("Tamanho") { item in
                let now = state.currentSize(item)
                if now != item.size {
                    Text(Fmt.size(now)).monospacedDigit().foregroundStyle(.green)
                        .help("Antes: \(Fmt.size(item.size))")
                } else {
                    Text(Fmt.size(item.size)).monospacedDigit()
                }
            }
                .width(min: 60, ideal: 80)
            TableColumn("Depois / Status") { item in
                if let job = state.videoJobs[item.url] { jobCell(job) } else { afterCell(item) }
            }
                .width(min: 220, ideal: 290)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            Button("Mostrar no Finder") {
                NSWorkspace.shared.activateFileViewerSelecting(items.filter { ids.contains($0.id) }.map(\.url))
            }
        }
    }

    @ViewBuilder
    private func jobCell(_ job: AppState.VideoJob) -> some View {
        switch job {
        case .queued:
            Label("Na fila", systemImage: "clock").foregroundStyle(.secondary)
        case .running(let p):
            HStack(spacing: 6) {
                ProgressView(value: p).frame(width: 90)
                Text("Comprimindo \(Int(p * 100))%").monospacedDigit()
            }
        case .done(let old, let new):
            let pct = Int(((1 - Double(new) / Double(max(old, 1))) * 100).rounded())
            Label("OK · \(Fmt.size(new)) (−\(pct)%)", systemImage: "checkmark.circle.fill")
                .monospacedDigit()
                .foregroundStyle(.green)
                .help("Antes: \(Fmt.size(old)). Agora: \(Fmt.size(new)).")
        case .failed(let why):
            Label("Erro: \(why)", systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red).lineLimit(1)
                .help(why)
        case .cancelled:
            Label("Cancelado", systemImage: "stop.circle").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func afterCell(_ item: ScanItem) -> some View {
        if let v = item.video {
            let pct = Int(((1 - Double(v.estimatedSize) / Double(max(item.size, 1))) * 100).rounded())
            if v.limited {
                HStack(spacing: 6) {
                    Picker("", selection: Binding(get: { v.mode }, set: { state.setVideoMode(item.id, $0) })) {
                        Text("Não comprimir").tag(CompressMode.skip)
                        Text("Leve").tag(CompressMode.light)
                        if v.codec != "AV1" {
                            Text("Forte").tag(CompressMode.strong)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    if v.mode == .skip {
                        Text("já compacto").foregroundStyle(.secondary)
                    } else {
                        Text("≈ \(Fmt.size(v.estimatedSize)) (−\(pct)%)")
                            .monospacedDigit()
                            .foregroundStyle(v.mode == .strong ? .orange : .yellow)
                    }
                }
                .help(v.codec == "AV1"
                      ? "AV1 já é um formato muito eficiente: só o nível Leve (~20% menor) funciona, e a conversão é lenta."
                      : "Leve: cerca de 25% menor, perda pequena de qualidade. Forte: cerca de 50% menor, perda de qualidade visível em cenas com muito movimento ou detalhe.")
            } else {
                Text("≈ \(Fmt.size(v.estimatedSize)) (−\(pct)%)")
                    .monospacedDigit().foregroundStyle(.green)
            }
        } else if let why = item.blockedReason {
            Label(why, systemImage: "minus.circle").foregroundStyle(.secondary)
        }
    }

    // MARK: Rodapé

    @ViewBuilder
    private func footer(selected: [ScanItem], before: Int64, after: Int64, lossy: Int) -> some View {
        HStack(spacing: 10) {
            Button("Selecionar todos") { state.setVideosSelected(in: state.videoFolderFilter, true) }
                .fixedSize()
            Button("Desmarcar") { state.setVideosSelected(in: state.videoFolderFilter, false) }
                .fixedSize()
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(state.videoFolderFilter.map { URL(fileURLWithPath: $0).lastPathComponent + ": " } ?? "")\(selected.count) vídeos · \(Fmt.size(before)) → ≈ \(Fmt.size(after))")
                    .font(.callout.monospacedDigit())
                    .lineLimit(1).truncationMode(.head)
                if lossy > 0 {
                    Text("\(lossy) com perda de qualidade (Leve/Forte)")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            .layoutPriority(-1)
            Button {
                state.compressReplace = false
                state.confirmingCompress = true
            } label: {
                Label("Comprimir e manter original", systemImage: "doc.on.doc")
            }
            .controlSize(.large)
            .fixedSize()
            .help("Salva a versão comprimida ao lado, sem mexer no original")
            .disabled(selected.isEmpty || state.compressing)
            Button {
                state.compressReplace = true
                state.confirmingCompress = true
            } label: {
                Label("Comprimir e substituir", systemImage: "arrow.down.right.and.arrow.up.left")
            }
            .buttonStyle(.borderedProminent).tint(.green)
            .controlSize(.large)
            .fixedSize()
            .help("A versão comprimida substitui o original, com o mesmo nome")
            .disabled(selected.isEmpty || state.compressing)
        }
    }
}

/// Lista de pastas com vídeos: cada pasta é comprimida separadamente.
struct VideoFolderList: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        let groups = state.videoGroups()
        List {
            Button {
                state.videoFolderFilter = nil
            } label: {
                folderRow(name: "Todas as pastas", path: nil, items: state.results[.videos] ?? [], icon: "square.stack.3d.up")
            }
            .buttonStyle(.plain)
            .listRowBackground(state.videoFolderFilter == nil ? Color.accentColor.opacity(0.15) : Color.clear)

            SwiftUI.Section("Pastas (\(groups.count))") {
                ForEach(groups, id: \.path) { g in
                    Button {
                        state.videoFolderFilter = g.path
                    } label: {
                        folderRow(name: URL(fileURLWithPath: g.path).lastPathComponent, path: g.path, items: g.items, icon: "folder")
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(state.videoFolderFilter == g.path ? Color.accentColor.opacity(0.15) : Color.clear)
                    .contextMenu {
                        Button("Mostrar no Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: g.path)) }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private func folderRow(name: String, path: String?, items: [ScanItem], icon: String) -> some View {
        let ok = items.filter { $0.blockedReason == nil }
        let sel = ok.filter(\.selected)
        let size = items.reduce(Int64(0)) { $0 + state.currentSize($1) }
        let est = ok.reduce(Int64(0)) { $0 + ($1.video?.estimatedSize ?? $1.size) } + (size - ok.reduce(Int64(0)) { $0 + $1.size })
        HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: Binding(
                get: { !ok.isEmpty && sel.count == ok.count },
                set: { v in state.setVideosSelected(in: path, v) }))
            .labelsHidden()
            .disabled(ok.isEmpty)
            Image(systemName: icon).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.body.weight(.medium)).lineLimit(1).truncationMode(.middle)
                if let path {
                    Text(path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head)
                }
                Text("\(items.count) vídeos · \(Fmt.size(size)) → ≈ \(Fmt.size(est))")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

import AppKit
import AVFoundation
import SharedCore
import Carbon.HIToolbox
import os

extension SettingsWindowController {
    func buildTemplateTab(tabView: NSTabView) {
                // ========== Tab 3: 模板 ==========
                let tmplTab = NSTabViewItem(identifier: "template")
                tmplTab.label = L10n.tr("模板", "Templates")
                let tmplView = NSView()
                let tmplOuter = NSStackView()
                tmplOuter.orientation = .vertical
                tmplOuter.alignment = .leading
                tmplOuter.spacing = 14
                tmplOuter.translatesAutoresizingMaskIntoConstraints = false
                tmplView.addSubview(tmplOuter)
                NSLayoutConstraint.activate([
                    tmplOuter.leadingAnchor.constraint(equalTo: tmplView.leadingAnchor, constant: 20),
                    tmplOuter.trailingAnchor.constraint(equalTo: tmplView.trailingAnchor, constant: -20),
                    tmplOuter.topAnchor.constraint(equalTo: tmplView.topAnchor, constant: 18),
                    tmplOuter.bottomAnchor.constraint(equalTo: tmplView.bottomAnchor, constant: -8),
                ])

                tmplOuter.addArrangedSubview(sectionHeader(L10n.tr("新建文件模板", "New File Templates"), subtitle: L10n.tr("勾选的会出现在「新建文件」子菜单", "Checked items appear in the New File submenu"), symbol: "doc.badge.plus"))

                listStack = NSStackView()
                listStack.orientation = .vertical
                listStack.alignment = .leading
                listStack.spacing = 4
                listStack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
                listStack.translatesAutoresizingMaskIntoConstraints = false

                let scrollView = NSScrollView()
                scrollView.documentView = listStack
                scrollView.hasVerticalScroller = true
                scrollView.drawsBackground = false
                scrollView.wantsLayer = true
                scrollView.layer?.cornerRadius = 10
                scrollView.layer?.borderWidth = 1
                scrollView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.08).cgColor
                scrollView.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.55).cgColor
                scrollView.hasHorizontalScroller = false
                scrollView.autohidesScrollers = true
                scrollView.borderType = .noBorder
                scrollView.drawsBackground = true
                scrollView.translatesAutoresizingMaskIntoConstraints = false
                scrollView.wantsLayer = true
                scrollView.layer?.cornerRadius = 10
                tmplOuter.addArrangedSubview(scrollView)
                NSLayoutConstraint.activate([
                    scrollView.heightAnchor.constraint(equalToConstant: 260),
                    listStack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
                    listStack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
                    listStack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
                    listStack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
                ])
                scrollView.widthAnchor.constraint(equalTo: tmplOuter.widthAnchor).isActive = true

                let buttons = NSStackView()
                buttons.orientation = .horizontal
                buttons.spacing = 10
                let add = NSButton(title: L10n.tr("添加模板", "Add Template"), target: self, action: #selector(addTemplate))
                add.setAccessibilityLabel(L10n.tr("添加模板", "Add template"))
                add.toolTip = L10n.tr("添加一个新建文件模板", "Add a new file template")
                add.bezelStyle = .inline
                add.isBordered = false
                add.wantsLayer = true
                add.layer?.cornerRadius = 7
                add.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
                add.contentTintColor = .white
                if let img = NSImage(systemSymbolName: "plus", accessibilityDescription: nil) { add.image = img; add.imagePosition = .imageLeading }
                add.controlSize = .small
                buttons.addArrangedSubview(add)
                let reset = NSButton(title: L10n.tr("恢复默认", "Restore Defaults"), target: self, action: #selector(resetTemplates))
                reset.setAccessibilityLabel(L10n.tr("恢复默认模板", "Restore default templates"))
                reset.toolTip = L10n.tr("仅恢复模板设置，不影响其他选项", "Restore templates only; keep other settings")
                reset.bezelStyle = .rounded
                reset.wantsLayer = true
                reset.layer?.cornerRadius = 7
                reset.layer?.borderWidth = 1
                reset.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.12).cgColor
                reset.controlSize = .small
                buttons.addArrangedSubview(reset)
                tmplOuter.addArrangedSubview(buttons)

                tmplTab.view = tmplView
                tabView.addTabViewItem(tmplTab)

    }
}

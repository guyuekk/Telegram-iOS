import Foundation
import Postbox
import SwiftSignalKit
import SyncCore

private final class ManagedChatListHolesState {
    private var holeDisposables: [ChatListHolesEntry: Disposable] = [:]
    private var additionalLatestHoleDisposable: (ChatListHole, Disposable)?
    private var additionalLatestArchiveHoleDisposable: (ChatListHole, Disposable)?
    
    func clearDisposables() -> [Disposable] {
        let disposables = Array(self.holeDisposables.values)
        self.holeDisposables.removeAll()
        return disposables
    }
    
    func update(entries: Set<ChatListHolesEntry>, additionalLatestHole: ChatListHole?, additionalLatestArchiveHole: ChatListHole?) -> (removed: [Disposable], added: [ChatListHolesEntry: MetaDisposable], addedAdditionalLatestHole: (ChatListHole, MetaDisposable)?, addedAdditionalLatestArchiveHole: (ChatListHole, MetaDisposable)?) {
        var removed: [Disposable] = []
        var added: [ChatListHolesEntry: MetaDisposable] = [:]
        
        for (entry, disposable) in self.holeDisposables {
            if !entries.contains(entry) {
                removed.append(disposable)
                self.holeDisposables.removeValue(forKey: entry)
            }
        }
        
        for entry in entries {
            if self.holeDisposables[entry] == nil {
                let disposable = MetaDisposable()
                self.holeDisposables[entry] = disposable
                added[entry] = disposable
            }
        }
        
        var addedAdditionalLatestHole: (ChatListHole, MetaDisposable)?
        var addedAdditionalLatestArchiveHole: (ChatListHole, MetaDisposable)?
        if self.holeDisposables.isEmpty {
            if self.additionalLatestHoleDisposable?.0 != additionalLatestHole {
                if let (_, disposable) = self.additionalLatestHoleDisposable {
                    removed.append(disposable)
                }
                if let additionalLatestHole = additionalLatestHole {
                    let disposable = MetaDisposable()
                    self.additionalLatestHoleDisposable = (additionalLatestHole, disposable)
                    addedAdditionalLatestHole = (additionalLatestHole, disposable)
                }
            }
            
            if additionalLatestHole == nil {
                if self.additionalLatestArchiveHoleDisposable?.0 != additionalLatestArchiveHole {
                    if let (_, disposable) = self.additionalLatestArchiveHoleDisposable {
                        removed.append(disposable)
                    }
                    if let additionalLatestArchiveHole = additionalLatestArchiveHole {
                        let disposable = MetaDisposable()
                        self.additionalLatestArchiveHoleDisposable = (additionalLatestArchiveHole, disposable)
                        addedAdditionalLatestArchiveHole = (additionalLatestArchiveHole, disposable)
                    }
                }
            }
        }
        
        return (removed, added, addedAdditionalLatestHole, addedAdditionalLatestArchiveHole)
    }
}

func managedChatListHoles(network: Network, postbox: Postbox, accountPeerId: PeerId) -> Signal<Void, NoError> {
    return Signal { _ in
        let state = Atomic(value: ManagedChatListHolesState())
        
        let topRootHoleKey: PostboxViewKey = .allChatListHoles(.root)
        let topArchiveHoleKey: PostboxViewKey = .allChatListHoles(Namespaces.PeerGroup.archive)
        let filtersKey: PostboxViewKey = .preferences(keys: Set([PreferencesKeys.chatListFilters]))
        let combinedView = postbox.combinedView(keys: [topRootHoleKey, topArchiveHoleKey, filtersKey])
        
        let disposable = combineLatest(postbox.chatListHolesView(), combinedView).start(next: { view, combinedView in
            var additionalLatestHole: ChatListHole?
            var additionalLatestArchiveHole: ChatListHole?
            
            if let preferencesView = combinedView.views[filtersKey] as? PreferencesView, let filtersState = preferencesView.values[PreferencesKeys.chatListFilters] as? ChatListFiltersState, !filtersState.filters.isEmpty {
                if let topRootHole = combinedView.views[topRootHoleKey] as? AllChatListHolesView, let hole = topRootHole.latestHole {
                    if !view.entries.contains(ChatListHolesEntry(groupId: .root, hole: hole)) {
                        additionalLatestHole = hole
                    }
                }
                if let topArchiveHole = combinedView.views[topArchiveHoleKey] as? AllChatListHolesView, let hole = topArchiveHole.latestHole {
                    if !view.entries.contains(ChatListHolesEntry(groupId: Namespaces.PeerGroup.archive, hole: hole)) {
                        additionalLatestArchiveHole = hole
                    }
                }
            }
            
            let (removed, added, addedAdditionalLatestHole, addedAdditionalLatestArchiveHole) = state.with { state in
                return state.update(entries: view.entries, additionalLatestHole: additionalLatestHole, additionalLatestArchiveHole: additionalLatestArchiveHole)
            }
            
            for disposable in removed {
                disposable.dispose()
            }
            
            for (entry, disposable) in added {
                disposable.set(fetchChatListHole(postbox: postbox, network: network, accountPeerId: accountPeerId, groupId: entry.groupId, hole: entry.hole).start())
            }
            
            if let (hole, disposable) = addedAdditionalLatestHole {
                disposable.set(fetchChatListHole(postbox: postbox, network: network, accountPeerId: accountPeerId, groupId: .root, hole: hole).start())
            }
            
            if let (hole, disposable) = addedAdditionalLatestArchiveHole {
                disposable.set(fetchChatListHole(postbox: postbox, network: network, accountPeerId: accountPeerId, groupId: Namespaces.PeerGroup.archive, hole: hole).start())
            }
        })
        
        return ActionDisposable {
            disposable.dispose()
            for disposable in state.with({ state -> [Disposable] in
                state.clearDisposables()
            }) {
                disposable.dispose()
            }
        }
    }
}

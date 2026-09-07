import SwiftUI
import Foundation

// MARK: - PickForMeView choice-list builder helpers

extension PickForMeView {
    func fictionChoiceList(selection: Binding<PickForMeFictionPreference?>) -> some View {
        VStack(spacing: 10) {
            ForEach(PickForMeFictionPreference.allCases) { option in
                let sub = devMode ? option.subtitle : option.userSubtitle
                PickForMeOptionButton(title: option.title, subtitle: sub, isSelected: selection.wrappedValue == option) {
                    selection.wrappedValue = selection.wrappedValue == option ? nil : option
                    errorText = nil
                    if selection.wrappedValue != nil { scrollToBottomToken = UUID() }
                }
            }
        }
    }

    func singleChoiceList<Option: PickForMeOption>(_ options: [Option], selection: Binding<Option?>) -> some View {
        VStack(spacing: 10) {
            ForEach(options) { option in
                PickForMeOptionButton(title: option.title, subtitle: option.subtitle, isSelected: selection.wrappedValue == option) {
                    selection.wrappedValue = selection.wrappedValue == option ? nil : option
                    errorText = nil
                    if selection.wrappedValue != nil { scrollToBottomToken = UUID() }
                }
            }
        }
    }

    func mediaFormatChoiceList(selection: Binding<PickForMeMediaFormat?>) -> some View {
        VStack(spacing: 10) {
            ForEach(PickForMeMediaFormat.allCases.filter { $0 != .both }) { option in
                PickForMeOptionButton(title: option.title, subtitle: option.subtitle, isSelected: selection.wrappedValue == option) {
                    selection.wrappedValue = option
                    errorText = nil
                    scrollToBottomToken = UUID()
                }
            }
        }
    }

    func primaryArchetypeChoiceList(selection: Binding<Set<PickForMeArchetype>>) -> some View {
        VStack(spacing: 10) {
            ForEach(PickForMeArchetype.allCases.filter { option in
                option != .noPreference && (option != .surprise || hasEnoughDataForSurprise)
            }) { option in
                PickForMeOptionButton(title: option.title, subtitle: option.subtitle, isSelected: selection.wrappedValue.contains(option)) {
                    selection.wrappedValue = [option]
                    answers.secondaryArchetypes.remove(option)
                    errorText = nil
                    scrollToBottomToken = UUID()
                }
            }
        }
    }

    func multiChoiceList<Option: PickForMeOption>(_ options: [Option], selection: Binding<Set<Option>>, maxCount: Int = .max) -> some View {
        VStack(spacing: 10) {
            ForEach(options) { option in
                let selectedNonAny = selection.wrappedValue.filter { !$0.isAnyOption }
                let atMax = !option.isAnyOption && !selection.wrappedValue.contains(option) && selectedNonAny.count >= maxCount
                PickForMeOptionButton(title: option.title, subtitle: option.subtitle, isSelected: selection.wrappedValue.contains(option)) {
                    guard !atMax else { return }
                    if option.isAnyOption {
                        selection.wrappedValue = [option]
                    } else {
                        selection.wrappedValue = selection.wrappedValue.filter { !$0.isAnyOption }
                        if selection.wrappedValue.contains(option) {
                            selection.wrappedValue.remove(option)
                        } else {
                            selection.wrappedValue.insert(option)
                        }
                    }
                    errorText = nil
                }
                .disabled(atMax)
            }
        }
    }

    func cappedMultiChoiceList<Option: PickForMeOption>(_ options: [Option], selection: Binding<Set<Option>>, maximumSelectionCount: Int) -> some View {
        VStack(spacing: 10) {
            ForEach(options) { option in
                PickForMeOptionButton(title: option.title, subtitle: option.subtitle, isSelected: selection.wrappedValue.contains(option)) {
                    if option.isAnyOption {
                        selection.wrappedValue = [option]
                    } else {
                        selection.wrappedValue = selection.wrappedValue.filter { !$0.isAnyOption }
                        if selection.wrappedValue.contains(option) {
                            selection.wrappedValue.remove(option)
                        } else if selection.wrappedValue.count < maximumSelectionCount {
                            selection.wrappedValue.insert(option)
                        } else {
                            errorText = "Choose up to \(maximumSelectionCount) options."
                            return
                        }
                    }

                    errorText = nil
                }
            }
        }
    }
}

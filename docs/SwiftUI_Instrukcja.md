CEL
Zbuduj aplikację TODO na iOS z 7 kartami przesuwanymi poziomo, efektami glass morphism, animacjami i efektem "książki" gdzie karty nachodzą na siebie.

KOLORY PASTELOWE
Utwórz rozszerzenie Color+Pastel.swift:

import SwiftUI

extension Color {
    // Purple (Shopping List)
    static let pastelPurple = Color(red: 0.85, green: 0.75, blue: 0.95)
    static let pastelPurpleLight = Color(red: 0.92, green: 0.85, blue: 0.98)
    
    // Green (Todo)
    static let pastelGreen = Color(red: 0.75, green: 0.92, blue: 0.75)
    static let pastelGreenLight = Color(red: 0.85, green: 0.97, blue: 0.85)
    
    // Yellow (Backlog)
    static let pastelYellow = Color(red: 0.98, green: 0.95, blue: 0.70)
    static let pastelYellowLight = Color(red: 1.0, green: 0.98, blue: 0.85)
    
    // Orange (Recurring)
    static let pastelOrange = Color(red: 1.0, green: 0.88, blue: 0.70)
    static let pastelOrangeLight = Color(red: 1.0, green: 0.93, blue: 0.85)
    
    // Blue (Household)
    static let pastelBlue = Color(red: 0.70, green: 0.85, blue: 0.98)
    static let pastelBlueLight = Color(red: 0.85, green: 0.92, blue: 1.0)
    
    // Pink (Areas)
    static let pastelPink = Color(red: 0.98, green: 0.75, blue: 0.85)
    static let pastelPinkLight = Color(red: 1.0, green: 0.87, blue: 0.92)
    
    // Gray (Settings)
    static let pastelGray = Color(red: 0.85, green: 0.85, blue: 0.85)
    static let pastelGrayLight = Color(red: 0.92, green: 0.92, blue: 0.92)
}
KLUCZOWE WYMAGANIA
Layout:
Pełny ekran iPhone'a - użyj GeometryReader i UIScreen.main.bounds
Peek width: 20px - minimalna widoczność kart po bokach
Card spacing: 8px - padding z każdej strony
Corner radius: 32px dla kart głównych, 16px dla wierszy zadań
Fonty:
Tytuły kart: .system(size: 28, weight: .bold)
Tekst zadań: .system(size: 15) (mały ale czytelny)
Opisy: .system(size: 14)
Animacje:
Slide przy swipowaniu: .spring(response: 0.35, dampingFraction: 0.8)
Dodawanie zadań: .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
Checkbox: .spring(response: 0.3, dampingFraction: 0.6)
Haptic feedback przy każdej akcji
Glass Effect:
Użyj .ultraThinMaterial (natywne iOS)
Gradient w tle każdej karty
Shadow: .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
STRUKTURA MODELI
TodoItem.swift:
import Foundation

struct TodoItem: Identifiable, Codable {
    let id: UUID
    var text: String
    var isCompleted: Bool
    var createdAt: Date
    
    init(id: UUID = UUID(), text: String, isCompleted: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.isCompleted = isCompleted
        self.createdAt = createdAt
    }
}
CardType.swift:
enum CardType: Int, CaseIterable, Identifiable {
    case shopping = 0, todo = 1, backlog = 2, recurring = 3, household = 4, areas = 5, settings = 6
    
    var id: Int { rawValue }
    
    var title: String {
        switch self {
        case .shopping: return "Shopping List"
        case .todo: return "Todo"
        case .backlog: return "Backlog"
        case .recurring: return "Recurring Tasks"
        case .household: return "Household"
        case .areas: return "Areas"
        case .settings: return "Settings"
        }
    }
    
    var color: Color {
        switch self {
        case .shopping: return .pastelPurple
        case .todo: return .pastelGreen
        case .backlog: return .pastelYellow
        case .recurring: return .pastelOrange
        case .household: return .pastelBlue
        case .areas: return .pastelPink
        case .settings: return .pastelGray
        }
    }
    
    var lightColor: Color {
        switch self {
        case .shopping: return .pastelPurpleLight
        case .todo: return .pastelGreenLight
        case .backlog: return .pastelYellowLight
        case .recurring: return .pastelOrangeLight
        case .household: return .pastelBlueLight
        case .areas: return .pastelPinkLight
        case .settings: return .pastelGrayLight
        }
    }
}
7 KART DO ZBUDOWANIA
ShoppingListCard - fioletowa, z koszykiem i word cloud modalem (gdy zaznaczysz zadanie, po 0.5s spada do koszyka)
TodoCard - zielona
BacklogCard - żółta
RecurringTasksCard - pomarańczowa
HouseholdCard - niebieska
AreasCard - różowa
SettingsCard - szara (bez zadań, tylko ustawienia z toggle'ami)
GŁÓWNY WIDOK - ContentView.swift
Zbuduj główny kontener z:

Header z tytułem "Tasks" i buttonem Settings (ikona: gearshape.fill)
Cards Container z efektem "książki":
Left peek - widoczne 20px brzegi poprzednich kart (max 3 karty, nakładające się co 5px)
Main card area - pełna karta z swipe gestures
Right peek - widoczne 20px brzegi następnych kart (max 3 karty)
Page Indicator - 7 kropek, aktywna ma szerokość 24px, nieaktywne 8px
Swipe logic:

Threshold: 50px
Left swipe → następna karta
Right swipe → poprzednia karta
Animacja: .spring(response: 0.35, dampingFraction: 0.8)
Haptic feedback po każdym swipe
KOMPONENTY DO ZBUDOWANIA
1. GlassCard.swift - Wrapper dla wszystkich kart
struct GlassCard<Content: View>: View {
    let cardType: CardType
    let content: Content
    
    var body: some View {
        ZStack {
            LinearGradient(colors: [cardType.lightColor, cardType.color], startPoint: .topLeading, endPoint: .bottomTrailing)
            Rectangle().fill(.ultraThinMaterial).opacity(0.3)
            content
        }
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
    }
}
2. CardPeekView.swift - Brzegi kart po bokach
struct CardPeekView: View {
    let cardType: CardType
    let isLeft: Bool
    
    var body: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(LinearGradient(colors: [cardType.color, cardType.lightColor], startPoint: isLeft ? .leading : .trailing, endPoint: isLeft ? .trailing : .leading))
            .frame(width: 25)
            .shadow(color: .black.opacity(0.15), radius: 4, x: isLeft ? -2 : 2, y: 0)
    }
}
3. TaskRow.swift - Wiersz zadania
struct TaskRow: View {
    @Binding var item: TodoItem
    let accentColor: Color
    let onDelete: () -> Void
    @State private var isAppearing = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Button(action: { 
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { 
                    item.isCompleted.toggle() 
                }
                hapticFeedback()
            }) {
                ZStack {
                    Circle().strokeBorder(item.isCompleted ? accentColor : accentColor.opacity(0.4), lineWidth: 2).frame(width: 24, height: 24)
                    if item.isCompleted {
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundColor(accentColor)
                    }
                }
            }
            
            Text(item.text).font(.system(size: 15)).foregroundColor(item.isCompleted ? .secondary : .primary).strikethrough(item.isCompleted, color: .secondary)
            Spacer()
            
            // Delete
            Button(action: { onDelete(); hapticFeedback() }) {
                Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundColor(.red.opacity(0.7))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial).shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2))
        .opacity(isAppearing ? 1 : 0).offset(y: isAppearing ? 0 : 20)
        .onAppear { withAnimation(.spring(response: 0.4, dampingFraction: 0.8).delay(0.1)) { isAppearing = true } }
    }
    
    private func hapticFeedback() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
SHOPPING LIST CARD - SPECJALNA FUNKCJONALNOŚĆ
ShoppingListCard musi mieć:

Koszyk - gdy zaznaczysz przedmiot (checkbox), po 0.5s automatycznie spada do koszyka
Przycisk "Koszyk (X)" - pojawia się na dole gdy koszyk nie jest pusty
Modal z Word Cloud - kliknięcie w koszyk otwiera modal z FlowLayout (word cloud)
Restore - kliknięcie w słowo w word cloud przywraca przedmiot na listę
BasketView (Modal):
struct BasketView: View {
    @Binding var items: [TodoItem]
    let onRestore: (TodoItem) -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                FlowLayout(spacing: 12) {
                    ForEach(items) { item in
                        Button(action: { onRestore(item); hapticFeedback() }) {
                            Text(item.text).font(.system(size: 15, weight: .medium))
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .background(Capsule().fill(Color.gray.opacity(0.2)))
                                .foregroundColor(.primary)
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Koszyk")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Zamknij") { dismiss() } } }
        }
    }
}
FlowLayout (Word Cloud):
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        FlowResult(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews, spacing: spacing).size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX, y: bounds.minY + result.frames[index].minY), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var frames: [CGRect] = []
        var size: CGSize = .zero
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if x + size.width > maxWidth && x > 0 {
                    x = 0; y += lineHeight + spacing; lineHeight = 0
                }
                frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }
            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}
SETTINGS CARD
Nie ma zadań, tylko sekcje ustawień:

Powiadomienia (toggle)
Tryb ciemny (toggle)
Język (button z chevron.right)
Motyw kolorystyczny (button)
Dane i przechowywanie (button)
O aplikacji - Wersja 1.0.0 (button)
Każda sekcja ma:

Ikonę SF Symbols w kwadracie 36x36
Tytuł (font 15, weight: .medium)
Subtitle lub wartość (font 13, secondary)
Toggle lub chevron.right
CHECKLIST
 7 kart z odpowiednimi kolorami
 Swipowanie działa płynnie
 Peek views (20px) po bokach z efektem książki
 Glass morphism (.ultraThinMaterial)
 Animacje przy dodawaniu/usuwaniu zadań
 Haptic feedback
 Shopping List - koszyk + word cloud
 Page indicator (7 kropek)
 Aplikacja na pełnym ekranie iPhone'a
 Fonty małe ale czytelne (15px dla zadań)
 Settings z toggleami
 Responsywność (iPhone SE, 15 Pro Max)
PRZYKŁADOWE DANE STARTOWE
Shopping List: ["Mleko", "Chleb"]
Todo: ["Napraw kran", "Sprzątnij choinkę"]
Backlog: ["Nauczyć się SwiftUI", "Przeczytać książkę"]
Recurring: ["Podlać rośliny", "Wywieźć śmieci"]
Household: ["Wymienić żarówkę", "Sprawdzić filtry"]
Areas: ["Zorganizować biuro", "Uporządkować garaż"]

import Foundation

@main struct VerifyModels {
    static func main() {
        let creature = Creature(id: "argentavis", arabic: "أرجنتافيس", english: "Argentavis", aliases: ["أرجي"])
        precondition(creature.matches("ارجنتافيس"))
        precondition(creature.matches("أَرْجِي"))
        precondition(creature.matches("ARGENT"))
        precondition(!creature.matches("ريكس"))
        precondition(Sighting.coordinate("٢٥٫٥") == 25.5)
        precondition(Sighting.coordinate("۲۵٫۵") == 25.5)
        precondition(Sighting.coordinate("100.1") == nil)
        precondition(Sighting.coordinate("nan") == nil)
        print("Arabic search and coordinate model checks passed")
    }
}

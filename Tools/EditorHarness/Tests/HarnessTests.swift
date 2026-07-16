import Testing
import Foundation
@testable import editor_harness

@Suite("Harness CLI")
struct HarnessCLITests {

    @Test func noArgumentsIsUsageError() async {
        let code = await HarnessRunner.run(arguments: [], print: { _ in }, printError: { _ in })
        #expect(code == 2)
    }

    @Test func unknownSubcommandIsUsageError() async {
        let code = await HarnessRunner.run(arguments: ["wat"], print: { _ in }, printError: { _ in })
        #expect(code == 2)
    }

    @Test func helpSucceeds() async {
        let code = await HarnessRunner.run(arguments: ["--help"], print: { _ in }, printError: { _ in })
        #expect(code == 0)
    }

    @Test func runWithoutScenarioIsUsageError() async {
        let code = await HarnessRunner.run(arguments: ["run"], print: { _ in }, printError: { _ in })
        #expect(code == 2)
    }

    @Test func missingScenarioFileFails() async {
        let code = await HarnessRunner.run(
            arguments: ["run", "/nope/missing.json"], print: { _ in }, printError: { _ in })
        #expect(code == 1)
    }
}

@Suite("Scenario decoding")
struct ScenarioTests {

    @Test func decodesStepsAndOperands() throws {
        let json = """
        { "name": "x", "open": "car.usda", "steps": [
            { "do": "select", "path": "/Car/Body" },
            { "do": "material.set", "input": "roughness", "number": 0.9 },
            { "do": "expect", "materialInput": "roughness", "isNull": true }
        ] }
        """
        let s = try JSONDecoder().decode(Scenario.self, from: Data(json.utf8))
        #expect(s.name == "x")
        #expect(s.steps.count == 3)
        #expect(s.steps[1].input == "roughness")
        #expect(s.steps[1].number == 0.9)
        #expect(s.steps[2].isNull == true)
    }

    @Test func rejectsScenarioMissingRequiredFields() {
        let json = #"{ "steps": [] }"#
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Scenario.self, from: Data(json.utf8))
        }
    }
}

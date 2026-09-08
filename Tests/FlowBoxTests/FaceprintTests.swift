import Testing
import SharedCore
import Foundation

@Suite("Faceprint")
struct FaceprintTests {

    @Test
    func cosineIdenticalIsOne() {
        #expect(abs(Faceprint.cosineSimilarity([1, 0, 0], [1, 0, 0]) - 1) < 0.001)
    }

    @Test
    func cosineOppositeIsMinusOne() {
        #expect(abs(Faceprint.cosineSimilarity([1, 0], [-1, 0]) - (-1)) < 0.001)
    }

    @Test
    func cosineOrthogonalIsZero() {
        #expect(abs(Faceprint.cosineSimilarity([1, 0], [0, 1]) - 0) < 0.001)
    }

    @Test
    func cosineDegenerateInputsAreZero() {
        #expect(Faceprint.cosineSimilarity([], []) == 0)
        #expect(Faceprint.cosineSimilarity([1, 2], [1]) == 0)
        #expect(Faceprint.cosineSimilarity([0, 0], [0, 0]) == 0)
    }

    @Test
    func averageMeanAndBadSamples() {
        #expect(Faceprint.average([]) == nil)
        let mean = Faceprint.average([[1, 2], [3, 4]])
        #expect(mean != nil)
        #expect(abs((mean?[0] ?? 0) - 2) < 0.001)
        #expect(abs((mean?[1] ?? 0) - 3) < 0.001)
        // 长度不一致的样本丢弃,只剩有效帧
        let partial = Faceprint.average([[1, 1], [2, 2, 2], [3, 3]])
        #expect(partial != nil)
        #expect(abs((partial?[0] ?? 0) - 2) < 0.001)
    }
}

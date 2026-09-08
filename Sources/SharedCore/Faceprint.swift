import Foundation

/// 主人脸特征向量的纯数值比对:余弦相似度 + 注册多帧平均。
/// Vision 侧的提取在 PresenceMonitor,此处只做可单元测试的纯计算,不依赖摄像头,
/// 因此 TestRunner 也能覆盖。
public enum Faceprint {

    /// 余弦相似度(-1~1,越大越像;空向量/长度不一致/零向量返回 0)
    public static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in 0 ..< a.count {
            let x = Double(a[i]), y = Double(b[i])
            dot += x * y
            na += x * x
            nb += y * y
        }
        guard na > 0, nb > 0 else { return 0 }
        return dot / (na.squareRoot() * nb.squareRoot())
    }

    /// 注册时多帧取平均(长度不一致的样本丢弃;无有效样本返回 nil)
    public static func average(_ samples: [[Float]]) -> [Float]? {
        guard let dim = samples.first?.count, dim > 0 else { return nil }
        let valid = samples.filter { $0.count == dim }
        guard !valid.isEmpty else { return nil }
        var mean = [Double](repeating: 0, count: dim)
        for s in valid {
            for i in 0 ..< dim { mean[i] += Double(s[i]) }
        }
        let n = Double(valid.count)
        return mean.map { Float($0 / n) }
    }
}

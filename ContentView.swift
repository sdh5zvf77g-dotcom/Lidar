import SwiftUI
import ARKit
import RealityKit
import UIKit

struct ContentView: View {
    @StateObject private var scanner = ScannerModel()
    @State private var groundOnly = true
    @State private var tolerance: Double = 0.12
    @State private var showingShare = false
    @State private var exportURL: URL?

    var body: some View {
        ZStack(alignment: .bottom) {
            ScannerView(scanner: scanner, groundOnly: groundOnly, tolerance: tolerance)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                HStack {
                    Label(scanner.status, systemImage: scanner.isSupported ? "dot.radiowaves.left.and.right" : "exclamationmark.triangle")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(scanner.triangleCount > 0 ? "\(scanner.triangleCount) faces" : "Scanning…")
                        .font(.caption)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)

                HStack {
                    Picker("View", selection: $groundOnly) {
                        Text("Ground Only").tag(true)
                        Text("Raw Scan").tag(false)
                    }
                    .pickerStyle(.segmented)
                }

                HStack {
                    Text("Ground tolerance")
                    Slider(value: $tolerance, in: 0.05...0.40, step: 0.01)
                    Text("\(Int(tolerance * 100)) cm")
                        .monospacedDigit()
                        .frame(width: 52, alignment: .trailing)
                }
                .font(.caption)

                HStack(spacing: 12) {
                    Button {
                        scanner.reset()
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        exportURL = scanner.exportOBJ(groundOnly: groundOnly, tolerance: tolerance)
                        showingShare = exportURL != nil
                    } label: {
                        Label("Export OBJ", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(scanner.triangleCount == 0)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding()
        }
        .sheet(isPresented: $showingShare) {
            if let exportURL {
                ShareSheet(items: [exportURL])
            }
        }
    }
}

struct ScannerView: UIViewRepresentable {
    @ObservedObject var scanner: ScannerModel
    let groundOnly: Bool
    let tolerance: Double

    func makeUIView(context: Context) -> ARView {
        scanner.attach(to: context.coordinator.view)
        return context.coordinator.view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        scanner.groundOnly = groundOnly
        scanner.tolerance = Float(tolerance)
        scanner.refreshVisualization()
    }

    func makeCoordinator() -> Coordinator { Coordinator(scanner: scanner) }

    final class Coordinator {
        let view: ARView
        init(scanner: ScannerModel) {
            view = ARView(frame: .zero)
            view.automaticallyConfigureSession = false
        }
    }
}

final class ScannerModel: NSObject, ObservableObject, ARSessionDelegate {
    @Published var status = "Starting LiDAR…"
    @Published var triangleCount = 0
    @Published var isSupported = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)

    var groundOnly = true
    var tolerance: Float = 0.12

    private weak var arView: ARView?
    private var anchors: [UUID: ARMeshAnchor] = [:]
    private var meshEntities: [UUID: ModelEntity] = [:]
    private let root = Entity()
    private let lock = NSLock()

    func attach(to view: ARView) {
        guard arView == nil else { return }
        arView = view
        view.scene.addAnchor(root)
        guard isSupported else {
            status = "LiDAR scene reconstruction is not supported"
            return
        }

        let config = ARWorldTrackingConfiguration()
        config.sceneReconstruction = .meshWithClassification
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        view.session.delegate = self
        view.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        status = "Walk slowly around the area"
    }

    func reset() {
        anchors.removeAll()
        meshEntities.values.forEach { $0.removeFromParent() }
        meshEntities.removeAll()
        triangleCount = 0
        arView?.session.run({
            let c = ARWorldTrackingConfiguration()
            c.sceneReconstruction = .meshWithClassification
            c.planeDetection = [.horizontal]
            c.environmentTexturing = .automatic
            return c
        }(), options: [.resetTracking, .removeExistingAnchors])
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            guard let mesh = anchor as? ARMeshAnchor else { continue }
            self.anchors[mesh.identifier] = mesh
            rebuild(mesh)
        }
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors {
            guard let mesh = anchor as? ARMeshAnchor else { continue }
            self.anchors[mesh.identifier] = mesh
            rebuild(mesh)
        }
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        for anchor in anchors {
            guard let mesh = anchor as? ARMeshAnchor else { continue }
            self.anchors.removeValue(forKey: mesh.identifier)
            meshEntities[mesh.identifier]?.removeFromParent()
            meshEntities.removeValue(forKey: mesh.identifier)
        }
        refreshCount()
    }

    func refreshVisualization() {
        for mesh in anchors.values { rebuild(mesh) }
    }

    private func rebuild(_ anchor: ARMeshAnchor) {
        guard let view = arView else { return }
        let geometry = groundOnly ? GroundFilter.makeGroundGeometry(from: anchor, tolerance: tolerance) : MeshBuilder.makeGeometry(from: anchor)
        guard let geometry else { return }

        let entity = ModelEntity(mesh: geometry, materials: [SimpleMaterial(color: .init(white: 0.82, alpha: 1), isMetallic: false)])
        entity.transform.matrix = anchor.transform
        entity.name = groundOnly ? "Ground" : "Raw"

        DispatchQueue.main.async {
            if let old = self.meshEntities[anchor.identifier] { old.removeFromParent() }
            self.root.addChild(entity)
            self.meshEntities[anchor.identifier] = entity
            self.refreshCount()
            if view.scene.anchors.contains(where: { $0 === self.root }) == false {
                view.scene.addAnchor(self.root)
            }
        }
    }

    private func refreshCount() {
        DispatchQueue.main.async { self.triangleCount = self.meshEntities.count }
    }

    func exportOBJ(groundOnly: Bool, tolerance: Double) -> URL? {
        let meshes = anchors.values.compactMap { anchor -> (vertices: [SIMD3<Float>], indices: [UInt32])? in
            let geo = groundOnly ? GroundFilter.makeData(from: anchor, tolerance: Float(tolerance)) : MeshBuilder.makeData(from: anchor)
            return geo
        }
        guard !meshes.isEmpty else { return nil }

        var obj = "# LiDAR Ground Mapper OBJ\n"
        var vertexOffset: UInt32 = 0
        for mesh in meshes {
            for v in mesh.vertices {
                obj += "v \(v.x) \(v.y) \(v.z)\n"
            }
            for i in stride(from: 0, to: mesh.indices.count, by: 3) {
                let a = mesh.indices[i] + vertexOffset + 1
                let b = mesh.indices[i + 1] + vertexOffset + 1
                let c = mesh.indices[i + 2] + vertexOffset + 1
                obj += "f \(a) \(b) \(c)\n"
            }
            vertexOffset += UInt32(mesh.vertices.count)
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("LiDARGround_\(Int(Date().timeIntervalSince1970)).obj")
        do { try obj.write(to: url, atomically: true, encoding: .utf8); return url } catch { return nil }
    }
}

struct MeshBuilder {
    static func makeData(from anchor: ARMeshAnchor) -> (vertices: [SIMD3<Float>], indices: [UInt32])? {
        let g = anchor.geometry
        let count = g.vertices.count
        guard count > 0 else { return nil }
        var vertices = [SIMD3<Float>](); vertices.reserveCapacity(count)
        for i in 0..<count { vertices.append(g.vertex(at: i)) }
        var indices = [UInt32](); indices.reserveCapacity(g.faces.count * 3)
        for i in 0..<g.faces.count {
            let tri = g.faceIndices(at: i)
            indices += [tri.0, tri.1, tri.2]
        }
        return (vertices, indices)
    }

    static func makeGeometry(from anchor: ARMeshAnchor) -> MeshResource? {
        guard let data = makeData(from: anchor) else { return nil }
        var desc = MeshDescriptor()
        desc.positions = MeshBuffer(data.vertices)
        desc.primitives = .triangles(data.indices)
        return try? MeshResource.generate(from: [desc])
    }
}

struct GroundFilter {
    static func makeData(from anchor: ARMeshAnchor, tolerance: Float) -> (vertices: [SIMD3<Float>], indices: [UInt32])? {
        let g = anchor.geometry
        guard g.vertices.count > 0 else { return nil }
        var vertices = [SIMD3<Float>](repeating: .zero, count: g.vertices.count)
        for i in 0..<g.vertices.count { vertices[i] = g.vertex(at: i) }

        // Build a local height map. For each XY cell, the lowest observed mesh point is treated as the candidate terrain.
        let cell: Float = 0.30
        var minY: [Int64: Float] = [:]
        func key(_ v: SIMD3<Float>) -> Int64 {
            let x = Int64(floor(v.x / cell))
            let z = Int64(floor(v.z / cell))
            return (x << 32) ^ (z & 0xffffffff)
        }
        for v in vertices {
            let k = key(v)
            minY[k] = min(minY[k] ?? .greatestFiniteMagnitude, v.y)
        }

        var indices = [UInt32]()
        indices.reserveCapacity(g.faces.count * 3)
        for face in 0..<g.faces.count {
            let ids = g.faceIndices(at: face)
            let a = vertices[Int(ids.0)], b = vertices[Int(ids.1)], c = vertices[Int(ids.2)]
            let center = (a + b + c) / 3
            let n = simd_normalize(simd_cross(b - a, c - a))
            let upward = simd_dot(n, SIMD3<Float>(0, 1, 0))
            let terrainY = minY[key(center)] ?? center.y
            let closeToTerrain = center.y <= terrainY + tolerance

            // Keep upward-facing terrain and very mildly sloped surfaces. Vertical vegetation is rejected.
            if upward > 0.45 && closeToTerrain {
                indices += [ids.0, ids.1, ids.2]
            }
        }
        guard !indices.isEmpty else { return nil }
        return (vertices, indices)
    }

    static func makeGeometry(from anchor: ARMeshAnchor, tolerance: Float) -> MeshResource? {
        guard let data = makeData(from: anchor, tolerance: tolerance) else { return nil }
        var desc = MeshDescriptor()
        desc.positions = MeshBuffer(data.vertices)
        desc.primitives = .triangles(data.indices)
        return try? MeshResource.generate(from: [desc])
    }
}

private extension ARMeshGeometry {
    func vertex(at index: Int) -> SIMD3<Float> {
        let ptr = vertices.buffer.contents().advanced(by: index * vertices.stride)
        return ptr.assumingMemoryBound(to: SIMD3<Float>.self).pointee
    }

    func faceIndices(at index: Int) -> (UInt32, UInt32, UInt32) {
        let ptr = faces.buffer.contents().advanced(by: index * faces.indexCountPerPrimitive * faces.bytesPerIndex)
        if faces.bytesPerIndex == 2 {
            let p = ptr.assumingMemoryBound(to: UInt16.self)
            return (UInt32(p[0]), UInt32(p[1]), UInt32(p[2]))
        } else {
            let p = ptr.assumingMemoryBound(to: UInt32.self)
            return (p[0], p[1], p[2])
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

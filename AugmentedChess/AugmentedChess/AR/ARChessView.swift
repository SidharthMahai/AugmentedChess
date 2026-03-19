import SwiftUI
import RealityKit
import ARKit

struct ARChessView: UIViewRepresentable {
    @ObservedObject var viewModel: GameViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> ARView {
        context.coordinator.makeARView()
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.sync(with: viewModel)
    }

    final class Coordinator: NSObject {
        private let viewModel: GameViewModel
        private weak var arView: ARView?
        private var currentTheme: BattleTheme

        private var boardAnchor: AnchorEntity?
        private var boardRoot = Entity()
        private var squareEntities: [Int: ModelEntity] = [:]
        private var pieceEntities: [Int: Entity] = [:]
        private var effectEntities: [Entity] = []
        private var capturedByWhiteEntities: [Entity] = []
        private var capturedByBlackEntities: [Entity] = []

        private var selectedHighlight: ModelEntity?
        private var legalHighlights: [Int: ModelEntity] = [:]
        private var hintFromHighlight: ModelEntity?
        private var hintToHighlight: ModelEntity?
        private var timerEntity: ModelEntity?
        private var lastTimerStamp: String = ""

        private let squareSize: Float = 0.04
        private let boardThickness: Float = 0.012
        private let pieceBaseY: Float = 0.0012
        private var lastMoveEventID: UUID?
        private var isAnimatingMove = false

        init(viewModel: GameViewModel) {
            self.viewModel = viewModel
            self.currentTheme = viewModel.selectedTheme
        }

        func makeARView() -> ARView {
            let arView = ARView(frame: .zero)
            self.arView = arView

            let config = ARWorldTrackingConfiguration()
            config.planeDetection = [.horizontal]
            config.environmentTexturing = .automatic
            arView.session.run(config)

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            arView.addGestureRecognizer(tap)
            arView.automaticallyConfigureSession = false

            return arView
        }

        func sync(with vm: GameViewModel) {
            if !vm.isBoardPlaced {
                if boardAnchor != nil {
                    clearBoard()
                }
                return
            }

            guard boardAnchor != nil else { return }
            currentTheme = vm.selectedTheme

            if let event = vm.latestMoveEvent, event.id != lastMoveEventID {
                animateMove(event, board: vm.board)
                lastMoveEventID = event.id
            } else {
                guard !isAnimatingMove else { return }
                syncPieces(with: vm.board)
            }

            updateHighlights(selected: vm.selectedSquare, legalTargets: vm.legalTargets, hint: vm.hintMove)
            updateTimer3D(seconds: vm.turnSecondsRemaining, side: vm.board.sideToMove)
        }

        @objc
        private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let arView else { return }
            let location = recognizer.location(in: arView)

            if !viewModel.isBoardPlaced {
                guard let result = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .horizontal).first else { return }
                placeBoard(at: result.worldTransform)
                return
            }

            if let square = squareIndex(from: arView.entity(at: location)) {
                viewModel.handleSquareTap(square)
            }
        }

        private func placeBoard(at worldTransform: simd_float4x4) {
            clearBoard()

            let anchor = AnchorEntity(world: worldTransform)
            boardAnchor = anchor
            boardRoot = Entity()
            boardRoot.position.y += boardThickness * 0.5

            buildBoardBase()
            orientBoardTowardUser(at: worldTransform)
            syncPieces(with: viewModel.board)
            anchor.addChild(boardRoot)
            arView?.scene.addAnchor(anchor)
            GameAudioManager.shared.playAmbientLoop()
            viewModel.boardPlaced()
        }

        private func orientBoardTowardUser(at worldTransform: simd_float4x4) {
            guard let arView else { return }
            let boardPosition = SIMD3<Float>(worldTransform.columns.3.x, worldTransform.columns.3.y, worldTransform.columns.3.z)
            let cameraPosition = arView.cameraTransform.translation
            var towardCamera = cameraPosition - boardPosition
            towardCamera.y = 0

            guard simd_length_squared(towardCamera) > 0.0001 else { return }
            let direction = simd_normalize(towardCamera)
            let yaw = atan2(direction.x, -direction.z)
            boardRoot.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        }

        private func clearBoard() {
            effectEntities.forEach { $0.removeFromParent() }
            effectEntities.removeAll()
            selectedHighlight?.removeFromParent()
            selectedHighlight = nil
            hintFromHighlight?.removeFromParent()
            hintFromHighlight = nil
            hintToHighlight?.removeFromParent()
            hintToHighlight = nil
            legalHighlights.values.forEach { $0.removeFromParent() }
            legalHighlights.removeAll()
            timerEntity?.removeFromParent()
            timerEntity = nil
            lastTimerStamp = ""
            pieceEntities.removeAll()
            squareEntities.removeAll()
            capturedByWhiteEntities.forEach { $0.removeFromParent() }
            capturedByBlackEntities.forEach { $0.removeFromParent() }
            capturedByWhiteEntities.removeAll()
            capturedByBlackEntities.removeAll()

            boardRoot.removeFromParent()
            boardAnchor?.removeFromParent()
            boardAnchor = nil
            isAnimatingMove = false
            GameAudioManager.shared.stopAmbientLoop()
        }

        private func buildBoardBase() {
            let boardSize = squareSize * 8
            let baseMesh = MeshResource.generateBox(size: [boardSize + 0.02, boardThickness, boardSize + 0.02], cornerRadius: 0.005)
            let baseMaterial = SimpleMaterial(
                color: UIColor(red: 0.10, green: 0.11, blue: 0.12, alpha: 1.0),
                roughness: 0.85,
                isMetallic: true
            )

            let base = ModelEntity(mesh: baseMesh, materials: [baseMaterial])
            base.position = [0, -boardThickness * 0.5, 0]
            boardRoot.addChild(base)

            // Forged-metal outer frame for a war-table silhouette.
            let frame = ModelEntity(
                mesh: MeshResource.generateBox(size: [boardSize + 0.04, 0.006, boardSize + 0.04], cornerRadius: 0.006),
                materials: [SimpleMaterial(color: UIColor(red: 0.12, green: 0.10, blue: 0.09, alpha: 1), roughness: 0.3, isMetallic: true)]
            )
            frame.position = [0, -0.002, 0]
            boardRoot.addChild(frame)

            for rank in 0..<8 {
                for file in 0..<8 {
                    let square = ChessSquare.index(file: file, rank: rank)
                    let tile = ModelEntity(mesh: MeshResource.generateBox(size: [squareSize * 0.98, 0.002, squareSize * 0.98], cornerRadius: 0.001))

                    let dark = currentTheme.boardDark
                    let light = currentTheme.boardLight
                    let tileMaterial = SimpleMaterial(
                        color: (file + rank).isMultiple(of: 2) ? dark : light,
                        roughness: 0.92,
                        isMetallic: false
                    )
                    tile.model?.materials = [tileMaterial]
                    tile.position = positionForSquare(square, y: 0.001)
                    tile.name = "square_\(square)"
                    tile.generateCollisionShapes(recursive: false)

                    boardRoot.addChild(tile)
                    squareEntities[square] = tile
                }
            }

            addAmbientEmbers()
            addBattlefieldLight()
            addRuneGridGlow()
            addFactionAtmosphere()
            buildTimerRig()
        }

        private func addBattlefieldLight() {
            let light = Entity()
            light.position = [0, 0.35, 0]
            light.components.set(PointLightComponent(
                color: .init(white: 0.85, alpha: 1),
                intensity: 1200,
                attenuationRadius: 1.5
            ))
            boardRoot.addChild(light)
        }

        private func addAmbientEmbers() {
            for i in 0..<18 {
                let ember = ModelEntity(mesh: .generateSphere(radius: 0.0016), materials: [SimpleMaterial(color: UIColor(red: 1, green: 0.45, blue: 0.22, alpha: 0.45), roughness: 0.4, isMetallic: false)])
                let x = Float.random(in: -0.20...0.20)
                let z = Float.random(in: -0.20...0.20)
                let y = Float.random(in: 0.015...0.06)
                ember.position = [x, y, z]
                ember.name = "ember_\(i)"
                boardRoot.addChild(ember)
                effectEntities.append(ember)
            }

            // Rune-like glow accents around the battlefield perimeter.
            for edge in 0..<16 {
                let rune = ModelEntity(
                    mesh: .generateBox(size: [0.005, 0.001, 0.012], cornerRadius: 0.0005),
                    materials: [SimpleMaterial(color: UIColor(red: 0.15, green: 0.50, blue: 0.55, alpha: 0.65), roughness: 0.2, isMetallic: false)]
                )
                let t = Float(edge) / 15.0
                let span = (squareSize * 8) * 0.5 + 0.006
                rune.position = [(-span + (2 * span * t)), 0.002, span]
                boardRoot.addChild(rune)
                effectEntities.append(rune)

                let mirrored = rune.clone(recursive: true)
                mirrored.position.z = -span
                boardRoot.addChild(mirrored)
                effectEntities.append(mirrored)
            }
        }

        private func addRuneGridGlow() {
            let boardHalf = (squareSize * 8) * 0.5
            let runeMatBlue = SimpleMaterial(color: currentTheme.runeNorth, roughness: 0.1, isMetallic: false)
            let runeMatGold = SimpleMaterial(color: currentTheme.runeSouth, roughness: 0.1, isMetallic: false)

            for i in 1..<8 {
                let offset = (Float(i) - 4.0) * squareSize
                let h = ModelEntity(mesh: .generateBox(size: [squareSize * 8.0, 0.0006, 0.0008]), materials: [i <= 4 ? runeMatBlue : runeMatGold])
                h.position = [0, 0.0021, offset]
                boardRoot.addChild(h)

                let v = ModelEntity(mesh: .generateBox(size: [0.0008, 0.0006, squareSize * 8.0]), materials: [i <= 4 ? runeMatBlue : runeMatGold])
                v.position = [offset, 0.0021, 0]
                boardRoot.addChild(v)
            }

            // Corner sigils (abstract, not copyrighted emblems).
            for sx in [-1.0 as Float, 1.0] {
                for sz in [-1.0 as Float, 1.0] {
                    let sigil = ModelEntity(mesh: .generateCone(height: 0.004, radius: 0.004), materials: [SimpleMaterial(color: UIColor(red: 0.85, green: 0.70, blue: 0.35, alpha: 0.75), isMetallic: true)])
                    sigil.position = [sx * (boardHalf - 0.018), 0.003, sz * (boardHalf - 0.018)]
                    boardRoot.addChild(sigil)
                }
            }
        }

        private func addFactionAtmosphere() {
            let boardHalf = (squareSize * 8) * 0.5

            let northLight = Entity()
            northLight.position = [0, 0.08, -boardHalf]
            northLight.components.set(PointLightComponent(color: UIColor(red: 0.55, green: 0.76, blue: 0.94, alpha: 1), intensity: 220, attenuationRadius: 0.22))
            boardRoot.addChild(northLight)

            let southLight = Entity()
            southLight.position = [0, 0.08, boardHalf]
            southLight.components.set(PointLightComponent(color: UIColor(red: 1.0, green: 0.50, blue: 0.24, alpha: 1), intensity: 220, attenuationRadius: 0.22))
            boardRoot.addChild(southLight)
        }

        private func buildTimerRig() {
            let boardHalf = (squareSize * 8) * 0.5
            let plate = ModelEntity(
                mesh: .generateBox(size: [0.080, 0.002, 0.028], cornerRadius: 0.003),
                materials: [SimpleMaterial(color: UIColor(red: 0.09, green: 0.09, blue: 0.10, alpha: 0.92), roughness: 0.25, isMetallic: true)]
            )
            // Position timer north of the opponent side.
            plate.position = [0, 0.012, boardHalf + 0.060]
            boardRoot.addChild(plate)
        }

        private func updateTimer3D(seconds: Int, side: PieceColor) {
            let stamp = "\(seconds)-\(side.rawValue)"
            guard stamp != lastTimerStamp else { return }
            lastTimerStamp = stamp

            timerEntity?.removeFromParent()
            let text = "\(seconds)s"
            let mesh = MeshResource.generateText(
                text,
                extrusionDepth: 0.0012,
                font: .boldSystemFont(ofSize: 0.018),
                containerFrame: .zero,
                alignment: .center,
                lineBreakMode: .byClipping
            )

            let tint = side == .white ? currentTheme.runeNorth : currentTheme.runeSouth
            let label = ModelEntity(mesh: mesh, materials: [SimpleMaterial(color: tint, roughness: 0.2, isMetallic: true)])
            let boardHalf = (squareSize * 8) * 0.5
            label.position = [-0.033, 0.014, boardHalf + 0.057]
            label.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
            boardRoot.addChild(label)
            timerEntity = label
        }

        private func syncPieces(with board: ChessBoard) {
            var aliveSquares = Set<Int>()

            for square in 0..<64 {
                guard let piece = board.piece(at: square) else { continue }
                aliveSquares.insert(square)

                if let existing = pieceEntities[square] {
                    existing.position = positionForSquare(square, y: pieceBaseY)
                    existing.name = "piece_\(square)"
                } else {
                    let entity = makePieceEntity(piece: piece, square: square)
                    pieceEntities[square] = entity
                    boardRoot.addChild(entity)
                }
            }

            let removed = pieceEntities.keys.filter { !aliveSquares.contains($0) }
            for square in removed {
                pieceEntities[square]?.removeFromParent()
                pieceEntities[square] = nil
            }
        }

        private func animateMove(_ event: MoveEvent, board: ChessBoard) {
            isAnimatingMove = true
            guard let moving = pieceEntities[event.move.from] ?? pieceEntities[event.move.to] else {
                syncPieces(with: board)
                isAnimatingMove = false
                return
            }

            // If UI updates placed the mover on destination before animation starts,
            // rewind it to source and animate continuously from there.
            if pieceEntities[event.move.from] == nil, pieceEntities[event.move.to] === moving {
                moving.position = positionForSquare(event.move.from, y: pieceBaseY)
                pieceEntities[event.move.to] = nil
                pieceEntities[event.move.from] = moving
            }

            if event.wasCapture, let captured = pieceEntities[event.move.to] {
                moveCapturedPieceToTray(captured, capturedBy: event.moverColor)
                triggerBattleEffect(at: event.move.to)
                pieceEntities[event.move.to] = nil
                GameAudioManager.shared.playCapture()
            }
            if !event.wasCapture {
                GameAudioManager.shared.playMove()
            }

            moving.name = "piece_\(event.move.to)"
            let start = moving.position
            let end = positionForSquare(event.move.to, y: pieceBaseY)
            let mid = SIMD3<Float>((start.x + end.x) * 0.5, pieceBaseY + 0.018, (start.z + end.z) * 0.5)
            moving.move(to: Transform(scale: [1, 1, 1], rotation: simd_quatf(), translation: mid), relativeTo: boardRoot, duration: 0.28, timingFunction: .easeOut)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                moving.move(to: Transform(scale: [1, 1, 1], rotation: simd_quatf(), translation: end), relativeTo: self.boardRoot, duration: 0.34, timingFunction: .easeInOut)
            }

            pieceEntities[event.move.from] = nil
            pieceEntities[event.move.to] = moving

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.68) {
                self.syncPieces(with: board)
                self.isAnimatingMove = false
            }
        }

        private func moveCapturedPieceToTray(_ entity: Entity, capturedBy capturer: PieceColor) {
            let slot = nextCaptureSlot(for: capturer)
            entity.name = "captured_\(UUID().uuidString.prefix(6))"
            entity.move(
                to: Transform(scale: [0.78, 0.78, 0.78], rotation: simd_quatf(angle: .pi * 0.55, axis: [1, 0, 0]), translation: slot),
                relativeTo: boardRoot,
                duration: 0.35,
                timingFunction: .easeOut
            )

            if capturer == .white {
                capturedByWhiteEntities.append(entity)
            } else {
                capturedByBlackEntities.append(entity)
            }
        }

        private func nextCaptureSlot(for capturer: PieceColor) -> SIMD3<Float> {
            let count = capturer == .white ? capturedByWhiteEntities.count : capturedByBlackEntities.count
            let col = Float(count % 8)
            let row = Float(count / 8)
            let x = (col - 3.5) * 0.018
            let boardHalf = (squareSize * 8) * 0.5
            let zBase = capturer == .white ? -(boardHalf + 0.065) : (boardHalf + 0.065)
            let z = capturer == .white ? (zBase - (row * 0.016)) : (zBase + (row * 0.016))
            return [x, pieceBaseY, z]
        }

        private func rebuildPieces(with board: ChessBoard) {
            pieceEntities.values.forEach { $0.removeFromParent() }
            pieceEntities.removeAll()
            syncPieces(with: board)
        }

        private func triggerBattleEffect(at square: Int) {
            for _ in 0..<8 {
                let spark = ModelEntity(mesh: .generateSphere(radius: 0.0018), materials: [SimpleMaterial(color: UIColor(red: 1.0, green: 0.62, blue: 0.25, alpha: 0.9), roughness: 0.3, isMetallic: true)])
                let origin = positionForSquare(square, y: 0.02)
                spark.position = origin
                boardRoot.addChild(spark)

                let drift = SIMD3<Float>(Float.random(in: -0.03...0.03), Float.random(in: 0.01...0.06), Float.random(in: -0.03...0.03))
                spark.move(to: Transform(scale: [0.001, 0.001, 0.001], rotation: simd_quatf(), translation: origin + drift), relativeTo: boardRoot, duration: 0.35, timingFunction: .easeOut)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
                    spark.removeFromParent()
                }
            }
        }

        private func updateHighlights(selected: Int?, legalTargets: Set<Int>, hint: ChessMove?) {
            selectedHighlight?.removeFromParent()
            selectedHighlight = nil
            legalHighlights.values.forEach { $0.removeFromParent() }
            legalHighlights.removeAll()
            hintFromHighlight?.removeFromParent()
            hintFromHighlight = nil
            hintToHighlight?.removeFromParent()
            hintToHighlight = nil

            if let selected {
                let highlight = makeHighlight(color: UIColor(red: 0.40, green: 0.73, blue: 1.0, alpha: 0.75), size: squareSize * 0.92, height: 0.003)
                highlight.position = positionForSquare(selected, y: 0.0035)
                boardRoot.addChild(highlight)
                selectedHighlight = highlight
            }

            for square in legalTargets {
                let target = makeHighlight(color: UIColor(red: 0.46, green: 0.90, blue: 0.58, alpha: 0.7), size: squareSize * 0.50, height: 0.0025)
                target.position = positionForSquare(square, y: 0.003)
                boardRoot.addChild(target)
                legalHighlights[square] = target
            }

            if let hint {
                let from = makeHighlight(color: UIColor(red: 0.99, green: 0.85, blue: 0.35, alpha: 0.75), size: squareSize * 0.86, height: 0.003)
                from.position = positionForSquare(hint.from, y: 0.004)
                boardRoot.addChild(from)
                hintFromHighlight = from

                let to = makeHighlight(color: UIColor(red: 1.0, green: 0.50, blue: 0.25, alpha: 0.8), size: squareSize * 0.86, height: 0.003)
                to.position = positionForSquare(hint.to, y: 0.004)
                boardRoot.addChild(to)
                hintToHighlight = to
            }
        }

        private func makeHighlight(color: UIColor, size: Float, height: Float) -> ModelEntity {
            ModelEntity(mesh: .generateBox(size: [size, height, size], cornerRadius: height * 0.5), materials: [SimpleMaterial(color: color, isMetallic: false)])
        }

        private func squareIndex(from entity: Entity?) -> Int? {
            var current = entity
            while let node = current {
                if node.name.hasPrefix("square_"), let idx = Int(node.name.replacingOccurrences(of: "square_", with: "")) {
                    return (0..<64).contains(idx) ? idx : nil
                }
                if node.name.hasPrefix("piece_"), let idx = Int(node.name.replacingOccurrences(of: "piece_", with: "")) {
                    return (0..<64).contains(idx) ? idx : nil
                }
                current = node.parent
            }
            return nil
        }

        private func positionForSquare(_ square: Int, y: Float) -> SIMD3<Float> {
            let file = Float(ChessSquare.file(square))
            let rank = Float(ChessSquare.rank(square))
            let x = (file - 3.5) * squareSize
            let z = (rank - 3.5) * squareSize
            return [x, y, z]
        }

        private func makePieceEntity(piece: Piece, square: Int) -> Entity {
            let root = Entity()
            root.name = "piece_\(square)"
            root.position = positionForSquare(square, y: pieceBaseY)

            let material = themedPieceMaterial(piece: piece)
            let base = ModelEntity(mesh: .generateCylinder(height: 0.006, radius: 0.013), materials: [material])
            base.position = [0, 0.003, 0]
            root.addChild(base)

            switch piece.type {
            case .pawn:
                let neck = ModelEntity(mesh: .generateCylinder(height: 0.014, radius: 0.0065), materials: [material])
                neck.position = [0, 0.012, 0]
                root.addChild(neck)
                let head = ModelEntity(mesh: .generateSphere(radius: 0.0068), materials: [material])
                head.position = [0, 0.022, 0]
                root.addChild(head)

            case .rook:
                let tower = ModelEntity(mesh: .generateCylinder(height: 0.024, radius: 0.010), materials: [material])
                tower.position = [0, 0.018, 0]
                root.addChild(tower)
                for i in 0..<4 {
                    let crenel = ModelEntity(mesh: .generateBox(size: [0.004, 0.004, 0.004]), materials: [material])
                    let angle = Float(i) * (.pi / 2)
                    crenel.position = [cos(angle) * 0.008, 0.031, sin(angle) * 0.008]
                    root.addChild(crenel)
                }

            case .knight:
                let body = ModelEntity(mesh: .generateCylinder(height: 0.016, radius: 0.0088), materials: [material])
                body.position = [0, 0.014, 0]
                root.addChild(body)
                let neck = ModelEntity(mesh: .generateBox(size: [0.008, 0.014, 0.006], cornerRadius: 0.002), materials: [material])
                neck.position = [0.003, 0.024, 0]
                root.addChild(neck)
                let head = ModelEntity(mesh: .generateSphere(radius: 0.005), materials: [material])
                head.position = [0.005, 0.032, 0]
                root.addChild(head)

            case .bishop:
                let stem = ModelEntity(mesh: .generateCylinder(height: 0.020, radius: 0.0072), materials: [material])
                stem.position = [0, 0.016, 0]
                root.addChild(stem)
                let hood = ModelEntity(mesh: .generateCone(height: 0.014, radius: 0.007), materials: [material])
                hood.position = [0, 0.031, 0]
                root.addChild(hood)
                let orb = ModelEntity(mesh: .generateSphere(radius: 0.0035), materials: [material])
                orb.position = [0, 0.039, 0]
                root.addChild(orb)

            case .queen:
                let stem = ModelEntity(mesh: .generateCylinder(height: 0.026, radius: 0.0085), materials: [material])
                stem.position = [0, 0.019, 0]
                root.addChild(stem)
                let crownRing = ModelEntity(mesh: .generateCylinder(height: 0.004, radius: 0.0105), materials: [material])
                crownRing.position = [0, 0.033, 0]
                root.addChild(crownRing)
                let crown = ModelEntity(mesh: .generateCone(height: 0.010, radius: 0.006), materials: [material])
                crown.position = [0, 0.040, 0]
                root.addChild(crown)

            case .king:
                let stem = ModelEntity(mesh: .generateCylinder(height: 0.028, radius: 0.0088), materials: [material])
                stem.position = [0, 0.020, 0]
                root.addChild(stem)
                let top = ModelEntity(mesh: .generateSphere(radius: 0.0048), materials: [material])
                top.position = [0, 0.038, 0]
                root.addChild(top)
                let crossV = ModelEntity(mesh: .generateBox(size: [0.002, 0.010, 0.002], cornerRadius: 0.0005), materials: [material])
                crossV.position = [0, 0.046, 0]
                root.addChild(crossV)
                let crossH = ModelEntity(mesh: .generateBox(size: [0.007, 0.002, 0.002], cornerRadius: 0.0005), materials: [material])
                crossH.position = [0, 0.046, 0]
                root.addChild(crossH)
            }

            let glow = Entity()
            glow.position = [0, 0.05, 0]
            let glowColor = piece.color == .white
                ? UIColor(red: 0.55, green: 0.80, blue: 1.0, alpha: 1)
                : UIColor(red: 1.0, green: 0.68, blue: 0.24, alpha: 1)
            glow.components.set(PointLightComponent(color: glowColor, intensity: 220, attenuationRadius: 0.12))
            root.addChild(glow)
            root.generateCollisionShapes(recursive: true)

            return root
        }

        private func themedPieceMaterial(piece: Piece) -> SimpleMaterial {
            if piece.color == .white {
                return SimpleMaterial(
                    color: currentTheme.whitePiece,
                    roughness: 0.30,
                    isMetallic: true
                )
            } else {
                return SimpleMaterial(
                    color: currentTheme.blackPiece,
                    roughness: 0.30,
                    isMetallic: true
                )
            }
        }
    }
}

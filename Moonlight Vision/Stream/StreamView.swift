//
//  StreamView.swift
//  Moonlight Vision
//

import SwiftUI
import os.log
import RealityKit
import GameController

struct StreamView: View {
    
    @Environment(\.scenePhase) var scenePhase
    @EnvironmentObject var mainModel: MainViewModel
    
    var screenCurvature: Float = 1.8
    
    @State private var dimPassthrough: Bool = false
    
    @Namespace var hoverNameSpace
    var hoverGroup: HoverEffectGroup {
        HoverEffectGroup(hoverNameSpace)
    }
    
    var body: some View {
        GeometryReader3D { proxy in
            ZStack {
                RealityView { content in
                    Task { [content] in
                        do {
                            let convertedSize = content.convert(proxy.frame(in: .local), from: .local, to: .scene)
                            let meshResource = try mainModel.curvedScreenBuilder.build(extents: convertedSize.extents, radius: screenCurvature)
                            
                            let entity = ModelEntity(
                                mesh: meshResource,
                                materials: [ mainModel.videoMaterial ]
                            )
                            entity.name = "CurvedScreen"
                            
                            entity.components.set(InputTargetComponent())
                            entity.components.set(
                                CollisionComponent(
                                    shapes: [],
                                    filter: CollisionFilter(group: [], mask: [])
                                )
                            )
                            
                            content.add(entity)
                            
                            Task(priority: .background) {
                                let shapeResource = try await ShapeResource.generateStaticMesh(from: meshResource)
                                entity.collision?.shapes = [shapeResource]
                            }
                        } catch {
                            print(error.localizedDescription)
                        }
                    }
                } update: { content in
                    guard let modelEntity = content.entities.first(where: { $0.name == "CurvedScreen" }) as? ModelEntity
                    else { return }
                    
                    do {
                        let convertedSize = content.convert(
                            proxy.frame(in: .local),
                            from: .local,
                            to: .scene
                        )
                        
                        let meshResource = try mainModel.curvedScreenBuilder.build(
                            extents: convertedSize.extents,
                            radius: screenCurvature
                        )
                        
                        modelEntity.model?.mesh = meshResource
                        Task(priority: .background) {
                            let shapeResource = try await ShapeResource.generateStaticMesh(from: meshResource)
                            modelEntity.collision?.shapes = [shapeResource]
                        }
                    } catch {
                        print(error.localizedDescription)
                    }
                }
                .handlesGameControllerEvents(matching: .gamepad)
                
                if let status = mainModel.status {
                    VStack {
                        ProgressView()
                        Text(status)
                    }
                }
            }
        }
        .ornament(attachmentAnchor: .scene(.topFront), contentAlignment: .bottom) {
            Button("Toggle Dimming", systemImage: dimPassthrough ? "moon.fill" : "moon") {
                dimPassthrough.toggle()
            }
            .labelStyle(.iconOnly)
            .hoverEffect { effect, isActive, proxy in
                effect.opacity(isActive ? 1.0 : 0)
            }
            .hoverEffectGroup(hoverGroup)
            .padding(12)
        }
        .preferredSurroundingsEffect(dimPassthrough ? .dark : .none)
        .onAppear {
            if let currentApp = mainModel.currentStreamingApp {
                mainModel.stream(app: currentApp)
            }
        }
        .onChange(of: scenePhase) { oldPhase, phase in
            switch phase {
            case .inactive, .background:
                mainModel.stopStream()
            default:
                break
            }
        }
    }
    
}

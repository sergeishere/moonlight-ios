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
    @State private var curvedScreenEntity: ModelEntity = ModelEntity()
    @State private var isWindowTransparent: Bool = false
    
    var body: some View {
        ZStack {
            GeometryReader3D { proxy in
                RealityView { content in
                    do {
                        
                        let convertedSize = content.convert(proxy.frame(in: .local), from: .local, to: .scene)
                        let meshResource = try mainModel.curvedScreenBuilder.build(
                            extents: convertedSize.extents,
                            radius: screenCurvature
                        )
                        
                        curvedScreenEntity = ModelEntity(
                            mesh: meshResource,
                            materials: [ mainModel.videoMaterial ]
                        )
                        
                        curvedScreenEntity.name = "CurvedScreen"
                        curvedScreenEntity.components.set(InputTargetComponent())
                        curvedScreenEntity.components.set(
                            CollisionComponent(
                                shapes: [],
                                filter: CollisionFilter(group: [], mask: [])
                            )
                        )
                        
                        curvedScreenEntity.components.set(OpacityComponent(opacity: 1.0))
                        
                        content.add(curvedScreenEntity)
                        Task(priority: .background) {
                            let shapeResource = try await ShapeResource.generateStaticMesh(from: meshResource)
                            curvedScreenEntity.collision?.shapes = [shapeResource]
                        }
                        
                    } catch {
                        print(error.localizedDescription)
                    }
                    
                } update: { content in
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
                        
                        curvedScreenEntity.model?.mesh = meshResource
                        
                        if isWindowTransparent {
                            curvedScreenEntity.components[OpacityComponent.self]?.opacity = 0.1
                            curvedScreenEntity.components[InputTargetComponent.self]?.isEnabled = false
                        } else {
                            curvedScreenEntity.components[OpacityComponent.self]?.opacity = 1
                            curvedScreenEntity.components[InputTargetComponent.self]?.isEnabled = true
                        }
                        
                        Task(priority: .background) {
                            let shapeResource = try await ShapeResource.generateStaticMesh(from: meshResource)
                            curvedScreenEntity.collision?.shapes = [shapeResource]
                        }
                    } catch {
                        print(error.localizedDescription)
                    }
                }
                .handlesGameControllerEvents(matching: .gamepad)
                                .onTapGesture {
                                    LiSendMouseButtonEvent(CChar(BUTTON_ACTION_PRESS), BUTTON_LEFT)
                                    LiSendMouseButtonEvent(CChar(BUTTON_ACTION_RELEASE), BUTTON_LEFT)
                                }
                .onLongPressGesture(minimumDuration: 0.3) {
                    LiSendMouseButtonEvent(CChar(BUTTON_ACTION_PRESS), BUTTON_RIGHT)
                    LiSendMouseButtonEvent(CChar(BUTTON_ACTION_RELEASE), BUTTON_RIGHT)
                }
                .gesture(
                    DragGesture()
                        .targetedToEntity(curvedScreenEntity)
                        .onChanged { value in
                            //                            let velocityLength = sqrt(pow(value.velocity.width, 2) + pow(value.velocity.height, 2))
                            let translationLength = sqrt(pow(value.translation.width, 2) + pow(value.translation.height, 2))
                            let normalizedX = value.translation.width / translationLength
                            let normalizedY = value.translation.height / translationLength
                            //                            let normalizedVelocityX = value.velocity.width / velocityLength
                            //                            let normalizedVelocityY = value.velocity.height / velocityLength
                            //                            print("Velocity", normalizedVelocityX, normalizedVelocityY)
                            let translationX = normalizedX * 13
                            let translationY = normalizedY * 13
                            //                            print("Translation", translationX, translationY)
                            LiSendMouseMoveEvent(
                                Int16(translationX),
                                Int16(translationY)
                            )
                        }
                )
                
                if let status = mainModel.status {
                    VStack {
                        ProgressView()
                        Text(status)
                    }
                }
            }
        }
        .glassBackgroundEffect()
        .ornament(attachmentAnchor: .scene(.topFront), contentAlignment: .bottom) {
            HStack {
                Button("Toggle Dimming", systemImage: dimPassthrough ? "moon.fill" : "moon") {
                    dimPassthrough.toggle()
                }
                .labelStyle(.iconOnly)
                
                Button("Toggle Opacity", systemImage: "circle.bottomrighthalf.pattern.checkered") {
                    withAnimation {
                        isWindowTransparent.toggle()
                    }
                }
                .labelStyle(.iconOnly)
            }
            .padding(12)
            .hoverEffect { effect, isActive, proxy in
                effect.opacity(isActive ? 1.0 : 0.1)
            }
        }
        .preferredSurroundingsEffect(dimPassthrough ? .dark : .none)
        .onAppear {
            dimPassthrough = true
            if let currentApp = mainModel.currentStreamingApp {
                mainModel.stream(app: currentApp)
            }
        }
        .onChange(of: scenePhase) { oldPhase, phase in
            
            print("Entering phase: \(phase) from \(oldPhase)")
            switch (oldPhase, phase) {
            case (_, .background):
                mainModel.stopStream()
            case (.background, .inactive):
                if let app = mainModel.currentStreamingApp {
                    mainModel.stream(app: app)
                }
            case (_, .active):
                dimPassthrough = true
            case (_, .inactive):
                dimPassthrough = false
            default:
                break
            }
        }
    }
    
}

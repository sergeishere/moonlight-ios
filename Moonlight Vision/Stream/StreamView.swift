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
    
    var screenCurvature: Float = 1.4
    
    @State private var dimPassthrough: Bool = false
    @State private var curvedScreenEntity: ModelEntity = ModelEntity()
    
    var body: some View {
        GeometryReader3D { proxy in
            ZStack {
                RealityView { content in
                    Task { [content] in
                        do {
                            let convertedSize = content.convert(proxy.frame(in: .local), from: .local, to: .scene)
                            let meshResource = try mainModel.curvedScreenBuilder.build(extents: convertedSize.extents, radius: screenCurvature)
                            
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
                                                       
                            content.add(curvedScreenEntity)
                            
                            Task(priority: .background) {
                                let shapeResource = try await ShapeResource.generateStaticMesh(from: meshResource)
                                curvedScreenEntity.collision?.shapes = [shapeResource]
                            }
                        } catch {
                            print(error.localizedDescription)
                        }
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
                        Task(priority: .background) {
                            let shapeResource = try await ShapeResource.generateStaticMesh(from: meshResource)
                            curvedScreenEntity.collision?.shapes = [shapeResource]
                        }
                    } catch {
                        print(error.localizedDescription)
                    }
                }
                .handlesGameControllerEvents(matching: .gamepad)
                .onTapGesture(perform: { (point: CGPoint) in
                    LiSendMousePositionEvent(Int16(point.x), Int16(point.y), Int16(proxy.size.width), Int16(proxy.size.height))
                    LiSendMouseButtonEvent(CChar(BUTTON_ACTION_PRESS), BUTTON_LEFT)
                    LiSendMouseButtonEvent(CChar(BUTTON_ACTION_RELEASE), BUTTON_LEFT)
                })
//                .onTapGesture {
//                    LiSendMouseButtonEvent(CChar(BUTTON_ACTION_PRESS), BUTTON_LEFT)
//                    LiSendMouseButtonEvent(CChar(BUTTON_ACTION_RELEASE), BUTTON_LEFT)
//                }
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
        .ornament(attachmentAnchor: .scene(.topFront), contentAlignment: .bottom) {
            Button("Toggle Dimming", systemImage: dimPassthrough ? "moon.fill" : "moon") {
                dimPassthrough.toggle()
            }
            .labelStyle(.iconOnly)
            .hoverEffect { effect, isActive, proxy in
                effect.opacity(isActive ? 1.0 : 0)
            }
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

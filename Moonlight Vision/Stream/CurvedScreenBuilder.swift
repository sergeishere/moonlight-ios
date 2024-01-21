//
//  CurvedScreenBuilder.swift
//  Moonlight
//
import RealityKit

final class CurvedScreenBuilder {
    
    private var vertices: [SIMD3<Float>]
    private var primitives: [UInt32]
    private let polygons: [UInt8]
    private var textureCoordinates: [simd_float2]
    
    let sectionsCount: Int
    let uvStep: Float
    let halfSectionsCount: Int
    
    init(sectionsCount: Int = 20) {
        self.sectionsCount = sectionsCount
        self.uvStep = 1 / Float(sectionsCount)
        self.halfSectionsCount = sectionsCount / 2
        
        self.polygons = [UInt8](repeating: 4, count: sectionsCount)
        self.primitives = [UInt32](0..<UInt32(sectionsCount*4))
        self.vertices = [SIMD3<Float>](repeating: [0,0,0], count: sectionsCount * 4)
        self.textureCoordinates = [simd_float2](repeating: [0,0], count: sectionsCount * 4)
    }
  
    func build(
        width: Float,
        height: Float,
        depth: Float,
        radius: Float
    ) throws -> MeshResource {
        
        let arcRad = (width / radius)
        let sectionRad = arcRad / Float(sectionsCount)
        let halfHeight = height/2
        let halfDepth = depth/2
        
        for sectionIndex in -halfSectionsCount..<halfSectionsCount {
            
            let index = (sectionIndex + halfSectionsCount) * 4
            
            let rad = sectionRad * Float(sectionIndex)
            let nextRad = sectionRad * Float(sectionIndex + 1)
            
            let startXPos = radius * sin(rad)
            let endXPos = radius * sin(nextRad)
            
            let startYPos = -radius * cos(rad) + radius - halfDepth
            let endYPos = -radius * cos(nextRad) + radius - halfDepth
            
            vertices[index] = [startXPos, -halfHeight, startYPos]
            vertices[index + 1] = [endXPos, -halfHeight, endYPos]
            vertices[index + 2] = [endXPos, halfHeight, endYPos]
            vertices[index + 3] = [startXPos, halfHeight, startYPos]
            
            let startUV = Float(sectionIndex + halfSectionsCount) * uvStep
            let endUV = Float(sectionIndex + halfSectionsCount + 1) * uvStep
            
            textureCoordinates[index] = [startUV, 0.0]
            textureCoordinates[index + 1] = [endUV, 0.0]
            textureCoordinates[index + 2] = [endUV, 1.0]
            textureCoordinates[index + 3] = [startUV, 1.0]
        }
        
        var descriptor = MeshDescriptor()
        descriptor.positions = MeshBuffers.Positions(vertices)
        descriptor.primitives = .polygons(polygons, primitives)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(textureCoordinates)
        
        let screenMesh = try MeshResource.generate(from: [descriptor])
        return screenMesh
        
    }
    
    func build(
        extents: SIMD3<Float>,
        radius: Float = 1.8
    ) throws -> MeshResource {
        try build(width: extents.x, height: extents.y, depth: extents.z, radius: radius)
    }
    
}

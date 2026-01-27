import AppKit
import CoreGraphics
import Foundation

protocol AnnotationToolProtocol {
    static func draw(_ annotation: Annotation, in context: CGContext, imageSize: CGSize, scaleFactor: CGFloat)
}

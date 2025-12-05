import SwiftUI
import UIKit
import ImageIO

struct GIFImage: View {
    let name: String

    var body: some View {
        GIFImageRepresentable(name: name)
    }
}

private final class ResizableGIFImageView: UIImageView {
    override var intrinsicContentSize: CGSize { .zero } // allow SwiftUI frame to drive the size
}

// UIKit-backed view that renders animated GIF as a SwiftUI view.
private struct GIFImageRepresentable: UIViewRepresentable {
    let name: String

    func makeUIView(context: Context) -> UIImageView {
        let imageView = ResizableGIFImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.isUserInteractionEnabled = true // allow SwiftUI gestures to pass through
        imageView.image = UIImage.animatedGIF(named: name) ?? UIImage(named: name)
        return imageView
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        uiView.image = UIImage.animatedGIF(named: name) ?? UIImage(named: name)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIImageView, context: Context) -> CGSize {
        let fallback = uiView.image?.size ?? CGSize(width: 1, height: 1)
        let width = proposal.width ?? fallback.width
        let height = proposal.height ?? fallback.height
        return CGSize(width: width, height: height)
    }
}

private extension UIImage {
    static func animatedGIF(named name: String) -> UIImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "gif"),
              let data = try? Data(contentsOf: url) else { return nil }
        return animatedGIF(data: data)
    }

    static func animatedGIF(data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }

        var images: [UIImage] = []
        var duration: TimeInterval = 0

        for i in 0..<count {
            if let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) {
                images.append(UIImage(cgImage: cgImage))
            }
            duration += frameDuration(at: i, source: source)
        }

        if duration == 0 { duration = Double(count) * (1.0 / 24.0) }
        return UIImage.animatedImage(with: images, duration: duration)
    }

    static func frameDuration(at index: Int, source: CGImageSource) -> TimeInterval {
        var frameDuration = 0.1
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any],
              let gifProps = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any] else {
            return frameDuration
        }

        if let unclamped = gifProps[kCGImagePropertyGIFUnclampedDelayTime as String] as? NSNumber {
            frameDuration = unclamped.doubleValue
        } else if let delay = gifProps[kCGImagePropertyGIFDelayTime as String] as? NSNumber {
            frameDuration = delay.doubleValue
        }
        if frameDuration < 0.02 { frameDuration = 0.1 }
        return frameDuration
    }
}

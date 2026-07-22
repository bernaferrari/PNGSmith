import SwiftUI

struct TransparencyCheckerboard: View {
    var body: some View {
        Canvas { context, size in
            let tile: CGFloat = 16
            let columns = Int(ceil(size.width / tile))
            let rows = Int(ceil(size.height / tile))
            for row in 0..<rows {
                for column in 0..<columns where (row + column).isMultiple(of: 2) {
                    context.fill(
                        Path(CGRect(
                            x: CGFloat(column) * tile,
                            y: CGFloat(row) * tile,
                            width: tile,
                            height: tile
                        )),
                        with: .color(.primary.opacity(0.035))
                    )
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

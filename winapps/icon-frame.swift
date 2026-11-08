// icon-frame <entrada.png> <saida.png>
// Põe o ícone de um programa Windows numa placa branca no formato dos ícones do
// macOS (grade de 1024 px da Apple: placa de 824 px em "squircle", sombra suave).
// Compilado pelo build.sh; usado pelo exe-icon.py ao criar atalhos.
import AppKit
import Foundation
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 3,
      let src = NSImage(contentsOfFile: args[1]),
      let icon = src.representations
          .compactMap({ ($0 as? NSBitmapImageRep)?.cgImage })
          .max(by: { $0.width < $1.width }) ?? src.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
    FileHandle.standardError.write("uso: icon-frame entrada.png saida.png\n".data(using: .utf8)!)
    exit(2)
}

let S = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0,
                          space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { exit(1) }

// Superelipse |x|^5 + |y|^5 = 1: bem próxima do contorno contínuo dos ícones da Apple.
func squircle(_ r: CGRect, n: Double = 5) -> CGPath {
    let p = CGMutablePath()
    let steps = 1440
    for i in 0..<steps {
        let t = Double(i) / Double(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = r.midX + r.width / 2 * copysign(pow(abs(c), 2 / n), c)
        let y = r.midY + r.height / 2 * copysign(pow(abs(s), 2 / n), s)
        if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
    }
    p.closeSubpath()
    return p
}

let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = squircle(plate)

// placa com sombra
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.28))
ctx.addPath(shape)
ctx.setFillColor(CGColor(gray: 1, alpha: 1))
ctx.fillPath()
ctx.restoreGState()

// leve gradiente vertical (branco → cinza muito claro), como os ícones do sistema
ctx.saveGState()
ctx.addPath(shape)
ctx.clip()
let grad = CGGradient(colorsSpace: cs, colors: [
    CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
    CGColor(srgbRed: 0.925, green: 0.93, blue: 0.945, alpha: 1),
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: plate.maxY), end: CGPoint(x: 0, y: plate.minY), options: [])
ctx.restoreGState()

// contorno sutil (some no fundo claro, separa no escuro)
ctx.addPath(shape)
ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.10))
ctx.setLineWidth(2)
ctx.strokePath()

// o ícone do programa, centralizado (~68% da placa)
let w = Double(icon.width), h = Double(icon.height)
var side = 560.0
ctx.interpolationQuality = .high
if max(w, h) < 128 {
    // ícone pequeno (32/48 px): amplia por um fator inteiro, sem borrar
    side = floor(560 / max(w, h)) * max(w, h)
    ctx.interpolationQuality = .none
}
let scale = side / max(w, h)
let dst = CGRect(x: (Double(S) - w * scale) / 2, y: (Double(S) - h * scale) / 2,
                 width: w * scale, height: h * scale)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 10, color: CGColor(gray: 0, alpha: 0.18))
ctx.draw(icon, in: dst)
ctx.restoreGState()

guard let out = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL,
                                                 UTType.png.identifier as CFString, 1, nil)
else { exit(1) }
CGImageDestinationAddImage(dest, out, nil)
exit(CGImageDestinationFinalize(dest) ? 0 : 1)

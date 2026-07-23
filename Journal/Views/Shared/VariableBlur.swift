//
//  VariableBlur.swift
//  Journal
//
//  Adapted from https://github.com/nikstar/VariableBlur
//
//  MIT License
//
//  Copyright (c) 2012-2023 Nikita Starshinov, Scott Chacon,
//  and others
//
//  Permission is hereby granted, free of charge, to any person obtaining
//  a copy of this software and associated documentation files (the
//  "Software"), to deal in the Software without restriction, including
//  without limitation the rights to use, copy, modify, merge, publish,
//  distribute, sublicense, and/or sell copies of the Software, and to
//  permit persons to whom the Software is furnished to do so, subject to
//  the following conditions:
//
//  The above copyright notice and this permission notice shall be included
//  in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
//  OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
//  MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
//  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
//  CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
//  TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
//  SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//

import CoreImage.CIFilterBuiltins
import QuartzCore
import SwiftUI
import UIKit

enum VariableBlurDirection {
  case blurredTopClearBottom
  case blurredBottomClearTop
}

struct VariableBlurView: UIViewRepresentable {
  var maxBlurRadius: CGFloat = 20
  var direction: VariableBlurDirection = .blurredTopClearBottom
  var startOffset: CGFloat = 0

  func makeUIView(context: Context) -> VariableBlurUIView {
    VariableBlurUIView(
      maxBlurRadius: maxBlurRadius,
      direction: direction,
      startOffset: startOffset
    )
  }

  func updateUIView(_ uiView: VariableBlurUIView, context: Context) {}
}

final class VariableBlurUIView: UIVisualEffectView {
  init(
    maxBlurRadius: CGFloat = 20,
    direction: VariableBlurDirection = .blurredTopClearBottom,
    startOffset: CGFloat = 0
  ) {
    super.init(effect: UIBlurEffect(style: .regular))

    let className = String("retliFAC".reversed())
    guard let filterClass = NSClassFromString(className) as? NSObject.Type else {
      print("[VariableBlur] Error: Can't find filter class")
      return
    }

    let selectorName = String(":epyThtiWretlif".reversed())
    guard
      let filter = filterClass.perform(
        NSSelectorFromString(selectorName),
        with: "variableBlur"
      )?.takeUnretainedValue() as? NSObject
    else {
      print("[VariableBlur] Error: Can't create variable blur filter")
      return
    }

    filter.setValue(maxBlurRadius, forKey: "inputRadius")
    filter.setValue(
      makeGradientImage(startOffset: startOffset, direction: direction),
      forKey: "inputMaskImage"
    )
    filter.setValue(true, forKey: "inputNormalizeEdges")

    let backdropLayer = subviews.first?.layer
    backdropLayer?.filters = [filter]

    for subview in subviews.dropFirst() {
      subview.alpha = 0
    }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func didMoveToWindow() {
    guard let window, let backdropLayer = subviews.first?.layer else {
      return
    }
    backdropLayer.setValue(
      window.traitCollection.displayScale,
      forKey: "scale"
    )
  }

  override func traitCollectionDidChange(
    _ previousTraitCollection: UITraitCollection?
  ) {
    // Calling super crashes while the private backdrop filter is installed.
  }

  private func makeGradientImage(
    width: CGFloat = 100,
    height: CGFloat = 100,
    startOffset: CGFloat,
    direction: VariableBlurDirection
  ) -> CGImage {
    let gradient = CIFilter.linearGradient()
    gradient.color0 = CIColor.black
    gradient.color1 = CIColor.clear
    gradient.point0 = CGPoint(x: 0, y: height)
    gradient.point1 = CGPoint(x: 0, y: startOffset * height)

    if case .blurredBottomClearTop = direction {
      gradient.point0.y = 0
      gradient.point1.y = height - gradient.point1.y
    }

    return CIContext().createCGImage(
      gradient.outputImage!,
      from: CGRect(x: 0, y: 0, width: width, height: height)
    )!
  }
}

import UIKit

@MainActor
final class UIKitDaySummaryCell: UICollectionViewCell {
    private static var titleFont: UIFont {
        let preferred = UIFont.preferredFont(forTextStyle: .title3)
        return UIFont.systemFont(ofSize: preferred.pointSize, weight: .semibold)
    }

    private let titleLabel = UILabel()
    private let canvas = UIKitDaySummaryCanvasView()
    private var model: DaySummaryRowModel?

    override init(frame: CGRect) {
        super.init(frame: frame)
        disableImplicitAnimations(for: layer)
        disableImplicitAnimations(for: contentView.layer)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        titleLabel.font = Self.titleFont
        titleLabel.textColor = .label
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        contentView.addSubview(titleLabel)
        contentView.addSubview(canvas)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityHint = String(localized: "Opens this day’s timeline")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func height(
        for model: DaySummaryRowModel,
        width: CGFloat
    ) -> CGFloat {
        ceil(titleFont.lineHeight) + 8
            + width * model.layoutRecipe.referenceHeight
                / DaySummaryLayoutRecipe.referenceWidth
    }

    func configure(
        model: DaySummaryRowModel,
        loadsDeferredContent: Bool
    ) {
        UIView.performWithoutAnimation {
            self.model = model
            let title = DaySummaryDatePresentation.dayTitle(for: model.summary.day)
            titleLabel.text = title
            accessibilityLabel = title
            canvas.configure(
                model: model,
                loadsDeferredContent: loadsDeferredContent
            )
            setNeedsLayout()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let titleHeight = ceil(Self.titleFont.lineHeight)
        titleLabel.frame = CGRect(
            x: 0,
            y: 0,
            width: contentView.bounds.width,
            height: titleHeight
        )
        canvas.frame = CGRect(
            x: 0,
            y: titleHeight + 8,
            width: contentView.bounds.width,
            height: max(0, contentView.bounds.height - titleHeight - 8)
        )
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        model = nil
        titleLabel.text = nil
        canvas.reset()
    }

    func zoomTiles(in viewport: UIView) -> [HomeFeedZoomTile] {
        guard let model else { return [] }
        return canvas.zoomTiles(summary: model.summary, in: viewport)
    }

    func didEndDisplaying() {
        canvas.reset()
    }
}

@MainActor
final class UIKitPeriodSummaryCell: UICollectionViewCell {
    private static var titleFont: UIFont {
        let preferred = UIFont.preferredFont(forTextStyle: .title2)
        return UIFont.systemFont(ofSize: preferred.pointSize, weight: .bold)
    }

    private let titleLabel = UILabel()
    private let canvas = UIKitPeriodSummaryCanvasView()
    private var model: PeriodSummaryRowModel?

    override init(frame: CGRect) {
        super.init(frame: frame)
        disableImplicitAnimations(for: layer)
        disableImplicitAnimations(for: contentView.layer)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        titleLabel.font = Self.titleFont
        titleLabel.textColor = .label
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        contentView.addSubview(titleLabel)
        contentView.addSubview(canvas)
        accessibilityHint = String(localized: "Opens the next level of this period")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func height(
        for model: PeriodSummaryRowModel,
        width: CGFloat
    ) -> CGFloat {
        ceil(titleFont.lineHeight) + 10
            + width * model.layoutRecipe.referenceHeight
                / PeriodSummaryLayoutRecipe.referenceWidth
    }

    func configure(
        model: PeriodSummaryRowModel,
        loadsDeferredContent: Bool,
        onOpenDay: @escaping (TimelineDayKey) -> Void
    ) {
        UIView.performWithoutAnimation {
            self.model = model
            let title: String
            switch model.summary.key {
            case .month(let month):
                title = PeriodSummaryDatePresentation.title(for: month)
            case .year(let year):
                title = PeriodSummaryDatePresentation.title(for: year)
            }
            titleLabel.text = title
            titleLabel.isAccessibilityElement = true
            titleLabel.accessibilityLabel = title
            titleLabel.accessibilityTraits = .button
            canvas.configure(
                model: model,
                loadsDeferredContent: loadsDeferredContent,
                onOpenDay: onOpenDay
            )
            setNeedsLayout()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let titleHeight = ceil(Self.titleFont.lineHeight)
        titleLabel.frame = CGRect(
            x: 0,
            y: 0,
            width: contentView.bounds.width,
            height: titleHeight
        )
        canvas.frame = CGRect(
            x: 0,
            y: titleHeight + 10,
            width: contentView.bounds.width,
            height: max(0, contentView.bounds.height - titleHeight - 10)
        )
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        model = nil
        titleLabel.text = nil
        canvas.reset()
    }

    func zoomTiles(in viewport: UIView) -> [HomeFeedZoomTile] {
        guard let model else { return [] }
        return canvas.zoomTiles(summary: model.summary, in: viewport)
    }

    func didEndDisplaying() {
        canvas.reset()
    }
}

@MainActor
final class UIKitHomeFeedStatusCell: UICollectionViewCell {
    private let symbolView = UIImageView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let button = UIButton(type: .system)
    private var action: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        symbolView.contentMode = .scaleAspectFit
        symbolView.tintColor = .secondaryLabel
        titleLabel.font = .preferredFont(forTextStyle: .title3)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        messageLabel.font = .preferredFont(forTextStyle: .body)
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 3
        button.configuration = .filled()
        button.addTarget(self, action: #selector(runAction), for: .touchUpInside)
        [symbolView, titleLabel, messageLabel, button].forEach(contentView.addSubview)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        symbol: String,
        title: String,
        message: String,
        actionTitle: String?,
        action: (() -> Void)?
    ) {
        symbolView.image = UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 34)
        )
        titleLabel.text = title
        messageLabel.text = message
        button.setTitle(actionTitle, for: .normal)
        button.isHidden = actionTitle == nil
        self.action = action
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = min(contentView.bounds.width - 32, 340)
        let originX = (contentView.bounds.width - width) / 2
        let buttonHeight: CGFloat = button.isHidden ? 0 : 44
        let totalHeight: CGFloat = 54 + 8 + 29 + 6 + 52
            + (button.isHidden ? 0 : 16 + buttonHeight)
        var y = (contentView.bounds.height - totalHeight) / 2
        symbolView.frame = CGRect(x: originX, y: y, width: width, height: 54)
        y += 62
        titleLabel.frame = CGRect(x: originX, y: y, width: width, height: 29)
        y += 35
        messageLabel.frame = CGRect(x: originX, y: y, width: width, height: 52)
        if !button.isHidden {
            y += 68
            button.frame = CGRect(
                x: originX + (width - 150) / 2,
                y: y,
                width: 150,
                height: buttonHeight
            )
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        action = nil
    }

    @objc private func runAction() {
        action?()
    }
}

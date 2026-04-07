# Cookbook App — Design Guidelines

> Minimal, practical design system for a Core Data learning project.
> UIKit + SnapKit | iOS 15+ | SF Pro system font

---

## 1. Color Palette

### Light Mode
| Token              | Hex       | Usage                              |
|--------------------|-----------|-------------------------------------|
| `primary`          | `#E8730E` | Buttons, active states, accents     |
| `primaryLight`     | `#FDEAD2` | Chip backgrounds, subtle highlights |
| `background`       | `#FFF9F2` | Main screen background              |
| `surface`          | `#FFFFFF` | Cards, cells, input fields          |
| `textPrimary`      | `#1C1C1E` | Headlines, body text                |
| `textSecondary`    | `#6B7280` | Captions, metadata, placeholders    |
| `divider`          | `#E5E7EB` | Separators, borders                 |
| `destructive`      | `#DC2626` | Delete actions                      |
| `star`             | `#F59E0B` | Rating stars                        |
| `favoriteHeart`    | `#EF4444` | Favorite icon filled                |

### Dark Mode
Use `UIColor.systemBackground`, `UIColor.secondarySystemBackground`, `UIColor.label`, `UIColor.secondaryLabel` as base. Override `primary` with `#F5943A` for better contrast on dark surfaces. Keep `star` and `favoriteHeart` unchanged.

### Implementation
```swift
enum AppColor {
    static let primary = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(hex: "#F5943A")
            : UIColor(hex: "#E8730E")
    }
    static let background = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? .systemBackground
            : UIColor(hex: "#FFF9F2")
    }
    static let surface = UIColor.secondarySystemGroupedBackground
    static let textPrimary = UIColor.label
    static let textSecondary = UIColor.secondaryLabel
    static let divider = UIColor.separator
    static let destructive = UIColor.systemRed
    static let star = UIColor(hex: "#F59E0B")
    static let favoriteHeart = UIColor.systemRed
    static let primaryLight = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(hex: "#3D2A1A")
            : UIColor(hex: "#FDEAD2")
    }
}
```

---

## 2. Typography

Use **SF Pro** (system font) exclusively. No custom fonts needed.

| Style         | Weight     | Size | Usage                        |
|---------------|------------|------|------------------------------|
| `largeTitle`  | Bold       | 34pt | Screen titles (nav bar)      |
| `title2`      | Bold       | 22pt | Section headers              |
| `headline`    | Semibold   | 17pt | Cell titles, recipe name     |
| `body`        | Regular    | 17pt | Body text, ingredients       |
| `callout`     | Regular    | 16pt | Form labels                  |
| `subheadline` | Regular    | 15pt | Metadata (cook time, servings) |
| `caption1`    | Regular    | 12pt | Timestamps, badge text       |

Use `UIFont.preferredFont(forTextStyle:)` for Dynamic Type support.

---

## 3. Spacing & Layout

| Token   | Value | Usage                            |
|---------|-------|----------------------------------|
| `xs`    | 4pt   | Icon-to-text gap                 |
| `sm`    | 8pt   | Intra-component spacing          |
| `md`    | 12pt  | Cell internal padding            |
| `lg`    | 16pt  | Section padding, screen margins  |
| `xl`    | 24pt  | Between major sections           |
| `xxl`   | 32pt  | Top/bottom screen padding        |

**Grid:** 16pt horizontal margins on all screens.
**Cell height:** Minimum 60pt for list rows (44pt minimum tap target).

---

## 4. Components

### Navigation Bar
- Large titles on root screens (Recipe List, Categories)
- Regular titles on pushed screens (Detail, Edit)
- Tint color: `primary`

### Table View Cells
- Recipe cell: 88pt height, 60x60pt thumbnail (8pt corner radius), 12pt internal padding
- Category cell: 52pt height, 28x28pt icon
- Accessory: disclosure indicator or custom (heart icon, count label)

### Buttons
- Primary: `primary` background, white text, 12pt corner radius, 48pt height
- Secondary: `primary` tint text, clear background, bordered
- Floating action: 56x56pt circle, `primary` background, shadow (opacity 0.15, offset 0,4, blur 12)

### Chips / Tags
- Height: 28pt, corner radius: 14pt (capsule)
- Active: `primary` background + white text
- Inactive: `primaryLight` background + `primary` text
- Horizontal scroll, 8pt gap between chips

### Form Inputs
- Use grouped UITableView style (inset grouped)
- Text fields: system style inside table cells
- Steppers/pickers: right-aligned accessory views

### Rating Stars
- 5 stars, 20pt size in cells, 28pt size in detail view
- Filled: `star` color, Empty: `divider` color
- Tappable for editing (44pt touch area per star)

### Empty State
- Centered vertically
- SF Symbol icon: `book.closed` at 64pt, `textSecondary` color
- Title: headline weight, "No recipes yet"
- Subtitle: subheadline, "Tap + to add your first recipe"

### Image Placeholder
- `photo.on.rectangle` SF Symbol centered
- Background: `primaryLight`
- Corner radius: 8pt (cells), 0pt (detail hero)

---

## 5. Iconography

Use **SF Symbols** exclusively.

| Action        | Symbol                    |
|---------------|---------------------------|
| Add           | `plus`                    |
| Edit          | `pencil`                  |
| Delete        | `trash`                   |
| Share         | `square.and.arrow.up`     |
| Favorite      | `heart` / `heart.fill`    |
| Search        | `magnifyingglass`         |
| Back          | `chevron.left`            |
| Cook time     | `clock`                   |
| Servings      | `person.2`                |
| Category      | `folder`                  |
| Photo         | `photo.on.rectangle`      |
| Reorder       | `line.3.horizontal`       |
| Star          | `star` / `star.fill`      |

---

## 6. Accessibility

- All tap targets: minimum 44x44pt
- Dynamic Type: support all text styles
- Color contrast: 4.5:1 minimum for text on backgrounds
- VoiceOver labels on all interactive elements
- `adjustsFontForContentSizeCategory = true` on all labels
- Meaningful `accessibilityLabel` on image-only buttons

---

## 7. Screen-Specific Notes

### Recipe List
- `UISearchController` embedded in navigation bar
- Filter chips: horizontal `UICollectionView` (44pt row height)
- Table sections: grouped by category, section header = category name

### Recipe Detail
- Hero image: 250pt height, content mode `scaleAspectFill`
- Sticky navigation bar becomes opaque on scroll
- Stats row: 3 items evenly spaced horizontally
- Floating edit button: 16pt from right edge, 16pt from safe area bottom

### Create/Edit Recipe
- Static `UITableView` with `insetGrouped` style
- Dynamic sections for ingredients/steps (add/delete rows)
- Image picker cell: 200pt height, full-width, tap to select

### Category Management
- Simple list, swipe actions for edit/delete
- Each row: icon (SF Symbol) + name + recipe count (right detail)

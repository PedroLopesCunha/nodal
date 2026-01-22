module BrandingHelper
  def organisation_branding_styles(organisation)
    return '' unless organisation

    primary = organisation.effective_primary_color
    secondary = organisation.effective_secondary_color
    primary_hover = darken_color(primary, 15)
    contrast = contrast_color(primary)
    primary_rgb = hex_to_rgb(primary)

    content_tag(:style) do
      <<~CSS.html_safe
        :root {
          --org-primary: #{primary};
          --org-primary-hover: #{primary_hover};
          --org-secondary: #{secondary};
          --org-primary-contrast: #{contrast};
          --org-primary-rgb: #{primary_rgb};
        }
      CSS
    end
  end

  private

  def darken_color(hex_color, percent)
    hex = hex_color.gsub('#', '')
    rgb = hex.scan(/../).map { |c| c.to_i(16) }
    darkened = rgb.map { |c| [(c * (100 - percent) / 100).round, 0].max }
    '#' + darkened.map { |c| c.to_s(16).rjust(2, '0') }.join
  end

  def contrast_color(hex_color)
    hex = hex_color.gsub('#', '')
    rgb = hex.scan(/../).map { |c| c.to_i(16) }
    luminance = (0.299 * rgb[0] + 0.587 * rgb[1] + 0.114 * rgb[2]) / 255
    luminance > 0.5 ? '#000000' : '#ffffff'
  end

  def hex_to_rgb(hex_color)
    hex = hex_color.gsub('#', '')
    rgb = hex.scan(/../).map { |c| c.to_i(16) }
    rgb.join(', ')
  end
end

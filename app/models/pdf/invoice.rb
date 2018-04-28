module PDF
  class Invoice < Base
    include HalfdaysHelper
    include MembershipsHelper

    attr_reader :invoice, :object, :isr_ref

    def initialize(invoice)
      @invoice = invoice
      @object = invoice.object
      # Reload object to be sure that the balance is up-to-date
      @missing_amount = ::Invoice.find(invoice.id).missing_amount
      @isr_ref = ISRReferenceNumber.new(invoice.id, @missing_amount)
      super
      header
      member_address
      content
      footer
      isr
    end

    private

    def info
      super.merge(Title: "#{::Invoice.model_name.human} #{invoice.id}")
    end

    def member_address
      member = invoice.member
      parts = [
        member.name,
        member.address.capitalize,
        "#{member.zip} #{member.city}"
      ]

      bounding_box [11.5.cm, bounds.height - 55], width: 8.cm, height: 2.5.cm do
        parts.each do |part|
          text part, valign: :top, leading: 2
          move_down 2
        end
      end
    end

    def header
      image acp_logo_io, at: [15, bounds.height - 20], width: 110
      bounding_box [155, bounds.height - 55], width: 200, height: 2.5.cm do
        text "#{::Invoice.model_name.human} N° #{invoice.id}", style: :bold, size: 16
        move_down 5
        text I18n.l(invoice.date)
        if invoice.object_type == 'Membership'
          move_down 5
          text membership_short_period(object), size: 10
        end
      end
    end

    def cur(amount, unit: '')
      number_to_currency(amount, unit: unit)
    end

    def content
      font_size 10
      data = [[
        ::Invoice.human_attribute_name(:description).downcase,
        "#{::Invoice.human_attribute_name(:amount).downcase} (CHF)"
      ]]

      case invoice.object_type
      when 'Membership'
        if object.basket_sizes_price.positive?
          object.basket_sizes.uniq.each do |basket_size|
            data << [
              membership_basket_size_description(basket_size),
              cur(object.basket_size_total_price(basket_size))
            ]
          end
        end
        unless object.baskets_annual_price_change.zero?
          data << [
            t('baskets_annual_price_change'),
            cur(object.baskets_annual_price_change)
          ]
        end
        if object.basket_complements_price.positive?
          object.basket_complements.uniq.each do |basket_complement|
            data << [
              membership_basket_complement_description(basket_complement),
              cur(object.basket_complement_total_price(basket_complement))
            ]
          end
        end
        unless object.basket_complements_annual_price_change.zero?
          data << [
            t('basket_complements_annual_price_change'),
            cur(object.basket_complements_annual_price_change)
          ]
        end
        object.distributions.uniq.each do |distribution|
          price = object.distribution_total_price(distribution)
          if price.positive?
            data << [
              membership_distribution_description(distribution),
              cur(price)
            ]
          end
        end
        unless object.halfday_works_annual_price.zero?
          data << [halfday_works_annual_price_description, cur(object.halfday_works_annual_price)]
        end
      when 'HalfdayParticipation'
        if object
          str = t_halfday('missed_halfday_participation_with_date', date: I18n.l(object.halfday.date))
          if invoice.paid_missing_halfday_works > 1
            str += " (#{invoice.paid_missing_halfday_works} #{HalfdayParticipation.human_attribute_name(:participants).downcase})"
          end
        elsif invoice.paid_missing_halfday_works == 1
          str = t_halfday('missed_halfday_participation')
        else
          str = t_halfday('missed_halfday_participations', count: invoice.paid_missing_halfday_works)
        end
        data << [str, cur(invoice.amount)]
      end

      if invoice.paid_memberships_amount.to_f.positive?
        data << [
          t('paid_memberships_amount'),
          cur(-invoice.paid_memberships_amount)
        ]
        data << [
          t('remaining_annual_memberships_amount'),
          cur(invoice.remaining_memberships_amount)
        ]
      elsif invoice.remaining_memberships_amount?
        data << [
          t('annual_memberships_amount'),
          cur(invoice.remaining_memberships_amount)
        ]
      end

      if invoice.memberships_amount?
        gross_amount = cur(invoice.memberships_amount).to_s
        gross_amount = "#{appendice_star}#{gross_amount}" if invoice.memberships_vat_amount&.positive?
        data << [invoice.memberships_amount_description, gross_amount]
      end

      if invoice.support_amount?
        data << [
          t('annual_support_amount'),
          cur(invoice.support_amount)
        ]
      end

      if @missing_amount != invoice.amount
        already_paid = invoice.amount - @missing_amount
        credit_amount = cur(-(already_paid + invoice.member.credit_amount))
        credit_amount = "#{appendice_star} #{credit_amount}" if invoice.member.credit_amount.positive?
        data << [t('credit_amount'), credit_amount]
        data << [t('missing_amount'), cur(@missing_amount)]
      elsif (invoice.memberships_amount? && invoice.support_amount?) || invoice.object_type != 'Membership'
        data << [t('total'), cur(invoice.amount)]
      end

      move_down 30
      table data, column_widths: [bounds.width - 120, 70], position: :center do |t|
        t.cells.borders = []
        t.cells.valign = :bottom
        t.cells.align = :right
        t.cells.inline_format = true
        t.cells.leading = 1

        t.columns(0).padding_right = 15
        t.columns(1).padding_left = 0
        t.columns(1).padding_right = 0
        t.row(0).borders = [:bottom]
        t.row(0).font_style = :bold
        t.rows(2..-1).padding_top = 0

        t.columns(0).rows(1..-1).filter do |cell|
          if cell.content.in? [t('paid_memberships_amount'), t('credit_amount')]
            t.row(cell.row).font_style = :italic
          end
        end
        t.columns(1).rows(1..-1).filter do |cell|
          t.row(cell.row).font_style = :italic if cell.content == ''
        end

        row = -1
        t.row(row).font_style = :bold

        if (@missing_amount != invoice.amount) || (invoice.memberships_amount? &&
            (invoice.support_amount? || !invoice.memberships_amount_description?)) ||
            invoice.object_type != 'Membership'
          t.columns(1).rows(row).borders = [:top]
          t.row(row).padding_top = 0
          t.row(row - 1).padding_bottom = 10
        end
        if invoice.memberships_amount_description?
          row -=
            if @missing_amount != invoice.amount
              invoice.support_amount? ? 4 : 3
            else
              invoice.support_amount? ? 3 : 1
            end

          t.columns(1).rows(row).borders = [:top]
          t.row(row).padding_top = 0
          t.row(row).padding_bottom = 15
          t.row(row - 1).padding_bottom = 10
        end
      end

      yy = 25
      reset_appendice_star

      if invoice.memberships_vat_amount&.positive?
        membership_vat_text = [
          "#{appendice_star} #{t('all_taxes_included')}",
          "#{cur(invoice.memberships_net_amount, unit: 'CHF')} #{t('without_taxes')}",
          "#{cur(invoice.memberships_vat_amount, unit: 'CHF')} #{t('vat')} (#{Current.acp.vat_membership_rate}%)"
        ].join(', ')
        bounding_box [0, y - 25], width: bounds.width - 24 do
          text membership_vat_text, width: 200, align: :right, style: :italic, size: 9
        end
        bounding_box [0, y - 5], width: bounds.width - 24 do
          text "N° #{t('vat')} #{Current.acp.vat_number}", width: 200, align: :right, style: :italic, size: 9
        end
        yy = 10
      end

      if invoice.member.credit_amount.positive?
        positive_credit_text = "#{appendice_star} #{t('extra_credit_amount')}"
        bounding_box [0, y - yy], width: bounds.width - 24 do
          text positive_credit_text, width: 200, align: :right, style: :italic, size: 9
        end
        yy = 10
      end

      bounding_box [0, y - yy], width: bounds.width - 24 do
        text Current.acp.invoice_info, width: 200, align: :right, style: :italic, size: 9
      end
    end

    def footer
      font_size 10
      bounding_box [0, 300], width: bounds.width, height: 50 do
        text Current.acp.invoice_footer, inline_format: true, align: :center
      end
    end

    def isr
      y = 273
      font_size 8
      bounding_box [0, y], width: bounds.width, height: y do
        image "#{Rails.root}/app/assets/images/isr.jpg",
          at: [0, y],
          width: bounds.width
        [10, 185].each do |x|
          text_box Current.acp.isr_payment_for, at: [x, y - 25], width: 120, height: 50, leading: 2
          text_box Current.acp.isr_in_favor_of, at: [x, y - 62], width: 120, height: 50, leading: 2
          text_box "N° #{::Invoice.model_name.human}: #{invoice.id}",
            at: [x, y - 108],
            width: 120,
            height: 50
        end
        font('OcrB')
        [87, 260].each do |x|
          text_box Current.acp.ccp,
            at: [x, y - 120],
            width: 100,
            height: 50,
            size: 10.5,
            character_spacing: 1
        end
        [64, 238].each do |x|
          text_box isr_ref.amount_without_cents,
            at: [x, y - 145],
            width: 50,
            height: 50,
            character_spacing: 1,
            size: 12,
            align: :right
          text_box isr_ref.amount_cents,
            at: [x + 75, y - 145],
            width: 50,
            height: 50,
            size: 12,
            character_spacing: 1
        end
        text_box isr_ref.ref,
          at: [353, y - 97],
          width: 370,
          height: 50,
          size: 10.5,
          character_spacing: 1
        text_box isr_ref.full_ref,
          at: [185, y - 241],
          width: 390,
          height: 50,
          size: 10.5,
          align: :right,
          character_spacing: 1
      end
    end

    def appendice_star
      @stars_count ||= 0
      @stars_count += 1
      '*' * @stars_count
    end

    def reset_appendice_star
      @stars_count = nil
    end

    def membership_basket_size_description(basket_size)
      baskets = object.baskets.where(basket_size: basket_size)
      "#{Basket.model_name.human}: #{basket_size.name} #{basket_sizes_price_info(baskets)}"
    end

    def membership_basket_complement_description(basket_complement)
      baskets =
        object
          .baskets
          .joins(:baskets_basket_complements)
          .where(baskets_basket_complements: { basket_complement: basket_complement })
      "#{basket_complement.name} #{basket_complements_price_info(baskets)}"
    end

    def membership_distribution_description(distribution)
      baskets = object.baskets.where(distribution: distribution)
      "#{Distribution.model_name.human}: #{distribution.name} #{distributions_price_info(baskets)}"
    end

    def halfday_works_annual_price_description
      i18n_scope = Current.acp.halfday_i18n_scope
      diff = object.annual_halfday_works - object.basket_size.annual_halfday_works
      if diff.positive?
        Membership.human_attribute_name("halfday_works_annual_price_reduction/#{i18n_scope}", count: diff)
      elsif diff.negative?
        Membership.human_attribute_name("halfday_works_annual_price_negative/#{i18n_scope}", count: diff)
      elsif object.halfday_works_annual_price.positive?
        Membership.human_attribute_name("halfday_works_annual_price_positive/#{i18n_scope}")
      else
        Membership.human_attribute_name("halfday_works_annual_price_default/#{i18n_scope}")
      end
    end

    def t(key, *args)
      I18n.t("invoices.pdf.#{key}", *args)
    end

    def t_halfday(key, *args)
      super(key, *args)
    end
  end
end

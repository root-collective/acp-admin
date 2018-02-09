class BasketsBasketComplement < ActiveRecord::Base
  belongs_to :basket
  belongs_to :basket_complement

  validates :price, numericality: { greater_than_or_equal_to: 0 }, presence: true
  validates :quantity, numericality: { greater_than_or_equal_to: 1 }, presence: true

  before_validation do
    self.price ||= basket_complement&.price
  end

  def description
    case quantity
    when 1 then basket_complement.name
    else "#{quantity} x #{basket_complement.name}"
    end
  end

  def total_price
    quantity * price
  end
end

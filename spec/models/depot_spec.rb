require 'rails_helper'

describe Depot do
  def member_ordered_names
    Depot.member_ordered.map(&:name)
  end

  specify '#member_ordered' do
    farm = create(:depot, price: 0, name: 'ferme')
    create(:depot, price: 2, name: 'poste')
    create(:depot, price: 1, name: 'gare', public_name: '')

    expect(member_ordered_names).to eq %w[ferme gare poste]

    Current.acp.update! depots_member_order_mode: 'price_desc'
    expect(member_ordered_names).to eq %w[poste gare ferme]

    Current.acp.update! depots_member_order_mode: 'name_asc'
    expect(member_ordered_names).to eq %w[ferme gare poste]

    farm.update! member_order_priority: 2
    expect(member_ordered_names).to eq %w[gare poste ferme]
  end

  describe '#deliveries_count' do
    it 'counts future deliveries when exits' do
      create_deliveries(2)
      depot = create(:depot)

      expect { create(:delivery, date: 1.year.from_now) }
        .to change { depot.reload.deliveries_counts }.from([2]).to([1])
    end
  end

  describe '#move_to' do
    it 'moves depot to a new position' do
      depot1 = create(:depot, id: 1)
      depot2 = create(:depot, id: 2)
      depot3 = create(:depot, id: 3)
      create(:membership, depot: depot1)
      create(:membership, depot: depot2)
      create(:membership, depot: depot3)

      expect { depot1.move_to(2, Delivery.first.id) }
        .to change { Depot.pluck(:id) }
        .from([1, 2, 3])
        .to([2, 1, 3])
    end

    it 'moves depot to a new position with delivery context respected' do
      depot1 = create(:depot, id: 1)
      create(:depot, id: 2)
      depot3 = create(:depot, id: 3)
      create(:membership, depot: depot1)
      create(:membership, depot: depot3)

      expect { depot1.move_to(2, Delivery.first.id) }
        .to change { Depot.pluck(:id) }
        .from([1, 2, 3])
        .to([2, 3, 1])
    end
  end
end

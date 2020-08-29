require 'rails_helper'

describe 'Memberships Renewal' do
  let(:basket_size) { create(:basket_size, name: 'Petit') }
  let(:depot) { create(:depot, name: 'Joli Lieu', fiscal_year: Current.fiscal_year) }
  let(:member) { create(:member) }

  before do
    Current.acp.update!(feature_flags: %w[open_renewal])
    Capybara.app_host = 'http://membres.ragedevert.test'
  end

  specify 'renew membership', freeze: '2020-09-30' do
    membership = create(:membership,
      member: member,
      basket_size: basket_size,
      depot: depot)
    DeliveriesHelper.create_deliveries(1, Current.acp.fiscal_year_for(2021))
    big_basket = create(:basket_size, name: 'Grand')
    membership.open_renewal!
    complement = create(:basket_complement,
      name: 'Oeufs',
      delivery_ids: Delivery.future_year.pluck(:id))

    login(member)

    within '#menu' do
      expect(page).to have_content 'Abonnement⤷ Renouvellement ?'
    end
    click_on 'Abonnement'

    choose 'Renouveler mon abonnement'
    click_on 'Suivant'

    choose "Grand"
    check "Oeufs"
    fill_in 'Remarque(s)', with: "Plus d'épinards!"

    click_on 'Confirmer'

    expect(page).to have_selector('.flash.notice',
      text: 'Votre abonnement a été renouvelé. Merci!')

    within '#menu' do
      expect(page).to have_content 'Abonnement⤷ En cours'
    end
    within 'main ul.details#2021' do
      expect(page).to have_content 'Période'
      expect(page).to have_content '1 janvier 2021 – 31 décembre 2021'
      expect(page).to have_content 'Panier'
      expect(page).to have_content 'Grand'
      expect(page).to have_content 'Complément'
      expect(page).to have_content 'Oeufs'
      expect(page).to have_content 'Dépôt'
      expect(page).to have_content 'Joli Lieu'
      expect(page).to have_content 'Livraisons'
      expect(page).to have_content '1'
      expect(page).to have_content '½ Journées'
      expect(page).to have_content '2 demandées'
      expect(page).to have_content 'Prix'
      expect(page).to have_content "CHF 34.20"
    end
    expect(membership.reload).to have_attributes(
      renew: true,
      renewal_annual_fee: nil,
      renewal_opened_at: Time.current,
      renewed_at: Time.current,
      renewal_note: "Plus d'épinards!")
    expect(membership).to be_renewed
    expect(membership.renewed_membership).to have_attributes(
      renew: true,
      started_on: Date.parse('2021-01-01'),
      ended_on: Date.parse('2021-12-31'),
      basket_size: big_basket,
      basket_complement_ids: [complement.id])
  end

  specify 'renew membership (with basket_price_extra)', freeze: '2020-09-30' do
    membership = create(:membership,
      member: member,
      basket_size: basket_size,
      depot: depot)
    DeliveriesHelper.create_deliveries(1, Current.acp.fiscal_year_for(2021))
    big_basket = create(:basket_size, name: 'Grand')
    membership.open_renewal!

    login(member)

    within '#menu' do
      expect(page).to have_content 'Abonnement⤷ Renouvellement ?'
    end
    click_on 'Abonnement'

    choose 'Renouveler mon abonnement'
    click_on 'Suivant'

    choose "Grand"
    choose "+ 8.-/panier"

    fill_in 'Remarque(s)', with: "Plus d'épinards!"

    save_and_open_page

    click_on 'Confirmer'

    expect(page).to have_selector('.flash.notice',
      text: 'Votre abonnement a été renouvelé. Merci!')

    within '#menu' do
      expect(page).to have_content 'Abonnement⤷ En cours'
    end
    within 'main ul.details#2021' do
      expect(page).to have_content 'Période'
      expect(page).to have_content '1 janvier 2021 – 31 décembre 2021'
      expect(page).to have_content 'Panier'
      expect(page).to have_content 'Grand'
      expect(page).to have_content 'Joli Lieu'
      expect(page).to have_content 'Livraisons'
      expect(page).to have_content '1'
      expect(page).to have_content '½ Journées'
      expect(page).to have_content '2 demandées'
      expect(page).to have_content 'Prix'
      expect(page).to have_content "CHF 38.00"
    end
    expect(membership.reload).to have_attributes(
      renew: true,
      renewal_annual_fee: nil,
      renewal_opened_at: Time.current,
      renewed_at: Time.current,
      renewal_note: "Plus d'épinards!",
      basket_price_extra: 0)
    expect(membership).to be_renewed
    expect(membership.renewed_membership).to have_attributes(
      renew: true,
      started_on: Date.parse('2021-01-01'),
      ended_on: Date.parse('2021-12-31'),
      basket_size: big_basket,
      basket_price_extra: 8)
  end


  specify 'cancel membership', freeze: '2020-09-30' do
    membership = create(:membership,
      member: member,
      basket_size: basket_size,
      depot: depot)
    DeliveriesHelper.create_deliveries(1, Current.acp.fiscal_year_for(2021))
    membership.open_renewal!

    login(member)

    within '#menu' do
      expect(page).to have_content 'Abonnement⤷ Renouvellement ?'
    end
    click_on 'Abonnement'

    choose 'Résilier mon abonnement'
    click_on 'Suivant'

    fill_in 'Remarque(s)', with: "Pas assez d'épinards!"
    check "Pour soutenir l'association, je continue à payer la cotisation annuelle dès l'an prochain."

    click_on 'Confirmer'

    expect(page).to have_selector('.flash.notice',
      text: 'Votre abonnement a été résilié.')

    within '#menu' do
      expect(page).to have_content 'Abonnement⤷ En cours'
    end
    expect(page).to have_content 'Votre abonnement a été résilié et se terminera après la livraison du 6 octobre 2020.'
    expect(membership.reload).to have_attributes(
      renew: false,
      renewal_opened_at: nil,
      renewal_annual_fee: 30,
      renewal_note: "Pas assez d'épinards!")
    expect(membership).to be_canceled
  end
end

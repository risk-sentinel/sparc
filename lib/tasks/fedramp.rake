# frozen_string_literal: true

# FedRAMP package tasks (#1354, #1384).
namespace :fedramp do
  # A local report, not a CI gate: it needs a checkout of the marketplace data.
  #
  #   git clone https://github.com/FedRAMP/marketplace-fedramp-gov-data
  #   bin/rails "fedramp:marketplace_check[marketplace-fedramp-gov-data]"
  #   FEDRAMP_MARKETPLACE_DIR=marketplace-fedramp-gov-data bin/rails fedramp:marketplace_check
  desc "Validate every package overview in a FedRAMP Marketplace data checkout (DIR, or FEDRAMP_MARKETPLACE_DIR)"
  task :marketplace_check, [ :dir ] => :environment do |_task, args|
    dir = args[:dir].presence || ENV["FEDRAMP_MARKETPLACE_DIR"].presence
    abort "Name the marketplace checkout: fedramp:marketplace_check[DIR], or set FEDRAMP_MARKETPLACE_DIR" unless dir

    begin
      puts FedrampMarketplaceCheck.call(dir).to_text
    rescue FedrampMarketplaceCheck::Error => e
      abort e.message
    end
  end
end

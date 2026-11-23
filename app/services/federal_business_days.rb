# frozen_string_literal: true

# #1390 — business days as FedRAMP counts them for notification deadlines:
# Monday to Friday, less the US federal holidays (5 U.S.C. 6103), each on the
# day it is observed: a holiday on a Saturday is observed the Friday before,
# one on a Sunday the Monday after (Executive Order 11582).
#
#   FederalBusinessDays.add(Date.new(2026, 11, 20), 5)    # => 2026-11-30 (Thanksgiving skipped)
#   FederalBusinessDays.add(Date.new(2026, 12, 1), -10)   # => 10 business days before
#   FederalBusinessDays.business_day?(Date.new(2026, 12, 25)) # => false
#
# Inauguration Day is a holiday only in the Washington, DC area and is not
# counted. Holidays a President declares by executive order are not known in
# advance and are not counted either.
module FederalBusinessDays
  extend self

  def business_day?(date)
    !date.saturday? && !date.sunday? && !holiday?(date)
  end

  def holiday?(date) = holidays(date.year).include?(date)

  # The date `count` business days after `date` (before it, when negative).
  # Zero returns the date itself.
  def add(date, count)
    date = date.to_date
    step = count.negative? ? -1 : 1
    count.abs.times do
      date += step
      date += step until business_day?(date)
    end
    date
  end

  # Observed federal holidays falling in a year. A New Year's Day on a
  # Saturday is observed on 31 December of the year before, so the next
  # year's is checked too.
  def holidays(year)
    @holidays ||= {}
    @holidays[year] ||= begin
      days = (year..year + 1).flat_map { |y| holidays_named(y) }
      days.select { |d| d.year == year }.to_set.freeze
    end
  end

  def holidays_named(year)
    [
      observed(Date.new(year, 1, 1)),   # New Year's Day
      nth_weekday(year, 1, 1, 3),       # Birthday of Martin Luther King, Jr.: third Monday in January
      nth_weekday(year, 2, 1, 3),       # Washington's Birthday: third Monday in February
      last_weekday(year, 5, 1),         # Memorial Day: last Monday in May
      observed(Date.new(year, 6, 19)),  # Juneteenth National Independence Day
      observed(Date.new(year, 7, 4)),   # Independence Day
      nth_weekday(year, 9, 1, 1),       # Labor Day: first Monday in September
      nth_weekday(year, 10, 1, 2),      # Columbus Day: second Monday in October
      observed(Date.new(year, 11, 11)), # Veterans Day
      nth_weekday(year, 11, 4, 4),      # Thanksgiving Day: fourth Thursday in November
      observed(Date.new(year, 12, 25))  # Christmas Day
    ]
  end

  def observed(date)
    return date - 1 if date.saturday?
    return date + 1 if date.sunday?

    date
  end

  # The nth given weekday (0 = Sunday) of a month.
  def nth_weekday(year, month, wday, nth)
    first = Date.new(year, month, 1)
    first + ((wday - first.wday) % 7) + (7 * (nth - 1))
  end

  def last_weekday(year, month, wday)
    last = Date.new(year, month, -1)
    last - ((last.wday - wday) % 7)
  end

  private_class_method :holidays_named, :observed, :nth_weekday, :last_weekday
end

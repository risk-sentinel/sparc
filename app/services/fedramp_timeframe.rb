# frozen_string_literal: true

# #1390 — a FedRAMP rule's timeframe (timeframe_type, timeframe_num) applied
# to a date or time: "bizdays" counts federal business days
# (FederalBusinessDays), "hours" clock hours, and "days", "weeks", "months"
# and "years" calendar time.
#
#   FedrampTimeframe.shift(Date.new(2026, 12, 1), "bizdays", 30, before: true)
#   FedrampTimeframe.shift(Time.current, "hours", 0.25)   # 15 minutes later
#
# A business-day shift of a time keeps its time of day.
module FedrampTimeframe
  module_function

  def shift(from, type, num, before: false)
    sign = before ? -1 : 1
    case type
    when "bizdays" then business_days(from, Integer(num) * sign)
    when "hours" then from + (num.to_f * 3600 * sign).round.seconds
    when "days", "weeks", "months", "years" then from + (Integer(num) * sign).public_send(type)
    else raise ArgumentError, "unknown FedRAMP timeframe type #{type.inspect}"
    end
  end

  # "10 business days", "6 hours", "15 minutes"
  def describe(type, num)
    if type == "hours" && num.to_f < 1
      minutes = (num.to_f * 60).round
      return "#{minutes} #{'minute'.pluralize(minutes)}"
    end

    num = num.to_f == num.to_i ? num.to_i : num
    unit = type == "bizdays" ? "business day" : type.singularize
    "#{num} #{unit.pluralize(num)}"
  end

  def business_days(from, count)
    return FederalBusinessDays.add(from, count) if from.instance_of?(Date)

    date = FederalBusinessDays.add(from.to_date, count)
    from.change(year: date.year, month: date.month, day: date.day)
  end
  private_class_method :business_days
end

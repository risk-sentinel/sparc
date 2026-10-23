# frozen_string_literal: true

# #1259 — brings the built-in roles up to their shipped defaults
# (BuiltInRoles) without undoing what an instance administrator decided.
#
# The `roles` seed section used to replace every built-in role's whole
# permission hash, display name, description, scope and sort order on each run.
# Any right an administrator had granted or revoked in Admin -> Roles or through
# /api/v1/roles was silently put back, with no audit event, on every deployment
# that bumped the section. This applies the shipped defaults one key at a time:
#
#   * a built-in role that does not exist is created with its shipped defaults;
#   * a key the administrator has not set takes the shipped default — a key new
#     in the code arrives, and a changed default reaches every role whose
#     administrator left that key alone;
#   * a key recorded in the role's `admin_overrides` is left exactly as the
#     administrator set it, and a shipped change it blocks is reported once;
#   * scope is never changed on a role that has assignments, because that
#     would silently change what every holder's grant means;
#   * a role an administrator created is never read or written.
#
# Every key changed and every shipped change skipped is written to the log and
# to the audit trail (`role_default_applied`, `role_default_skipped`), with no
# user: the actor is the deployment. Running it again changes nothing.
#
# NIST 800-53: AC-2 (account management), AC-3, AC-6 (least privilege),
# AU-12 (audit record generation), CM-3 (configuration change control),
# CM-6 (configuration settings).
class BuiltInRoleSeeder
  Change = Struct.new(:role, :key, :from, :to, keyword_init: true)
  Skip   = Struct.new(:role, :key, :value, :shipped, :reason, keyword_init: true)

  Result = Struct.new(:created, :changes, :skips, keyword_init: true) do
    def summary
      "#{created.size} created, #{changes.size} default(s) applied, " \
        "#{skips.size} shipped change(s) skipped"
    end

    def lines
      changes.map { |c| "#{c.role}: #{c.key} #{c.from.inspect} -> #{c.to.inspect} (shipped default)" } +
        skips.map { |s| "#{s.role}: #{s.key} kept #{s.value.inspect}, shipped #{s.shipped.inspect} (#{s.reason})" }
    end
  end

  SKIPPED_FOR_OVERRIDE    = "administrator override"
  SKIPPED_FOR_ASSIGNMENTS = "role has assignments"

  def self.call = new.call

  def call
    @result = Result.new(created: [], changes: [], skips: [])
    BuiltInRoles.all.each_value do |definition|
      role = Role.find_by(name: definition[:name])
      role ? reconcile(role, definition) : create(definition)
    end
    @result
  end

  private

  def create(definition)
    Role.create!(
      definition.slice(:name, *BuiltInRoles::ATTRIBUTES.map(&:to_sym)).merge(
        permissions: definition[:permissions].select { |_key, granted| granted }
      )
    )
    @result.created << definition[:name]
  end

  def reconcile(role, definition)
    changes = []
    skips = []

    (Role::PERMISSION_KEYS + BuiltInRoles::ATTRIBUTES).each do |key|
      shipped = Role.comparable(key, BuiltInRoles.default_for(definition[:name], key))
      current = role.current_value(key)

      if role.admin_overridden?(key)
        skips << skip_override(role, key, current, shipped)
      elsif current != shipped
        if key == "scope" && role.user_roles.exists?
          skips << Skip.new(role: role.name, key: key, value: current, shipped: shipped,
                            reason: SKIPPED_FOR_ASSIGNMENTS)
        else
          apply(role, key, shipped)
          changes << Change.new(role: role.name, key: key, from: current, to: shipped)
        end
      end
    end

    role.save! if role.changed?
    record(role, changes, skips.compact)
  end

  # An overridden key is never written. The shipped default stored with the
  # override moves to the current one so the same skipped change is reported
  # once, not on every run; a skip is reported only while the administrator's
  # value actually differs from what ships.
  def skip_override(role, key, current, shipped)
    recorded = role.admin_overrides[key]
    return nil if recorded == shipped

    role.admin_overrides = role.admin_overrides.merge(key => shipped)
    return nil if current == shipped

    Skip.new(role: role.name, key: key, value: current, shipped: shipped, reason: SKIPPED_FOR_OVERRIDE)
  end

  # A revoked default is removed rather than stored as `false`: the seeds have
  # only ever written granted keys, so an explicit `false` in a role's hash
  # stays a mark of the role editor or the API (the upgrade relies on it).
  def apply(role, key, value)
    if BuiltInRoles::ATTRIBUTES.include?(key)
      role.public_send("#{key}=", value)
    elsif value
      role.permissions = role.permissions.to_h.merge(key => true)
    else
      role.permissions = role.permissions.to_h.except(key)
    end
  end

  def record(role, changes, skips)
    changes.each do |change|
      log("role_default_applied", role, change.to_h.except(:role))
      @result.changes << change
    end
    skips.each do |skip|
      log("role_default_skipped", role, skip.to_h.except(:role))
      @result.skips << skip
    end
  end

  def log(action, role, details)
    Rails.logger.info("[roles seed] #{action} #{role.name} #{details.to_json}")
    AuditEvent.log(action: action, subject: role,
                   metadata: { role_name: role.name, source: "seed" }.merge(details))
  end
end

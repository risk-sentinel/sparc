module ApplicationHelper
  SSP_STATUS_COLORS = {
    'Implemented'              => '#27ae60',
    'Partially Implemented'    => '#f39c12',
    'Planned'                  => '#3498db',
    'Alternative Implementation' => '#9b59b6',
    'Not Applicable'           => '#95a5a6',
    'Not Implemented'          => '#e74c3c'
  }.freeze

  TPR_STATUS_COLORS = {
    'Pass'            => '#27ae60',
    'Partial'         => '#f39c12',
    'Fail'            => '#e74c3c',
    'Not Tested'      => '#95a5a6',
    'Not Applicable'  => '#bdc3c7'
  }.freeze

  def ssp_status_color(status, _count = 0)
    SSP_STATUS_COLORS[status] || '#7f8c8d'
  end

  def tpr_status_color(status, _count = 0)
    TPR_STATUS_COLORS[status] || '#7f8c8d'
  end
end

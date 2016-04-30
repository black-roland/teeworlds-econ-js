# Parse ID of weapon item to human readable string
#
# @param {String} id
# @return {String}
#
module.exports.parseWeapon = (id) ->
  return 'suicide' if id == '-1'
  return ['hammer', 'gun', 'shotgun', 'rocket', 'laser', 'katana'][parseInt id]

# Escape econ command
#
# @param {String} input
# @return {String}
#
module.exports.escape = (input) ->
  # escape quotes
  string = input.replace /"/g, '\\"'

  # escape line breaks
  string = string.replace /\n/g, '\\n'

  return string
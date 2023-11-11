local powershell = require "powershell"
-- TODO: tests

describe("setup", function()
  it("works with default", function() assert("my first function with param = Hello!", powershell.hello()) end)

  it("works with custom var", function()
    plugin.setup { opt = "custom" }
    assert("my first function with param = custom", plugin.hello())
  end)
end)

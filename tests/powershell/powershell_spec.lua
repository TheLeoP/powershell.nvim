local powershell = require "powershell"
-- TODO: tests

describe("setup", function()
  it("works with default", function() assert("my first function with param = Hello!", powershell.hello()) end)
end)

ExUnit.start()

# Ensure LocalStack is running and set up test resources
:inets.start()
Compressr.Test.LocalStack.ensure_running!()
Compressr.Test.LocalStack.reset_resources!()

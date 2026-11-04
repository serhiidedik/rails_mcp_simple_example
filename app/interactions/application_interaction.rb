# Base class for all interactions. Business logic lives here, never in controllers,
# MCP tools or models, so that every delivery channel runs the same code. Subclasses
# declare typed inputs (an allowlist: unknown inputs are dropped) and implement #execute.
#
# Failure contract, relied on by every adapter:
# - an expected failure (invalid input, failed validation) is reported through #errors;
# - a missing record raises ActiveRecord::RecordNotFound from #execute;
# - a change by someone who is not the owner raises OwnerOnly::NotOwner from #execute.
class ApplicationInteraction < ActiveInteraction::Base
end

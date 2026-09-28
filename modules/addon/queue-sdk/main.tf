# modules/addon/queue-sdk  (AWS + Azure)
#
# NO-OP module by design. With the SDK trigger mode the agent polls the Matillion
# control plane directly over the SDK — there is NO queue, adapter, or other
# cloud infrastructure to provision. This module exists only so the composer's
# declared path resolves and so the polling configuration (poll interval, max
# concurrent runs) has a single typed home that the compute modules can read.

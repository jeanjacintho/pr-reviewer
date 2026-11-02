CMD_PREFIX="jeanjacintho"
REVIEW_TIMEOUT_SECS=1200
TEST_TIMEOUT_SECS=900
CODEX_MODEL=""                                   # default when a repo in repos.json sets no model
DEEP_PARALLEL=3                                  # engine calls at once in a deep review
STAGE_TIMEOUT_SECS=600                           # timeout of each deep review stage
GH_RETRY_ATTEMPTS=4                              # tries per GitHub call that fails transiently
GH_RETRY_DELAY=3                                 # seconds before the 2nd try; grows linearly

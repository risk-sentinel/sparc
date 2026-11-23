# frozen_string_literal: true

# #1390 part G — a received version's review exported as Markdown
# (ReceivedDocumentReviewExport), to read and share with the provider out of
# band. Requested as `.md`.
Mime::Type.register "text/markdown", :md unless Mime::Type.lookup_by_extension(:md)

class ImportOpml
  include Sidekiq::Worker
  include OpmlImporter
  sidekiq_options :queue => :opml
  def perform(filetext, user_id)
    import_opml filetext, user_id
    user = User.find(user_id)
    PlusMailer.opml_imported(user).deliver
  rescue LibXML::XML::Error => e
    ap "OPML parsing error; ignoring"
  end
end
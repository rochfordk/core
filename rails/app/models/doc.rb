# Copyright 2013, Dell
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governnig permissions and
# limitations under the License.
#

class Doc < ActiveRecord::Base

  attr_accessible :id, :name, :description, :order, :barclamp_id, :parent_id

  belongs_to :barclamp
  belongs_to :parent, :class_name => "Doc"
  has_many :children, :class_name => "Doc", :foreign_key => "parent_id"

  validates_uniqueness_of :name, :scope=>:barclamp_id, :on => :create, :case_sensitive => false, :message => I18n.t("db.notunique", :default=>"Doc handle must be unique")

  scope :roots, where(:parent_id=>nil)
  scope :roots_by_barclamp, lambda { |barclamp_id| where(:parent_id=>nil, :barclamp_id=>barclamp_id) }

  def <=>(b)
    x = order <=> b.order if order and b.order
    x = name <=> b.name if x == 0
    return x
  end

  def self.root_directory
    File.join('../doc')
  end


  # creates the table of contents from the files
  def self.gen_doc_index
    # load barclamp docs
    Barclamp.order(:id).each { |bc| Doc.discover_docs bc }
    Doc.make_index if Rails.env.eql? 'development'
    Doc.all
  end


  def self.make_index name='README.md'

    index = File.open File.join(Rails.root, '..', 'doc', name), 'w'
    index << "_Autogenerated, do not edit!_\n#OpenCrowbar Documentation Index"
    Doc.all.sort.each do |d|
      index << "\n#{"  "*d.level}1. [#{d.description}](/doc#{d.name})"
    end
    index << "\n\n > Generated #{DateTime.current}"
    index.close

  end


  def self.topic_expand(name, html=true)
    text = "\n"
    topic = Doc.find_by_name name
    if topic.children.size > 0
      topic.children.each do |t|
        file = page_path root_directory, t.name
        if File.exist? file
          raw = IO.read(file)
          text += (html ? BlueCloth.new(raw).to_html : raw)
          text += topic_expand(t.name, html)
        end
      end
    end
    return text
  end

  # scan the directories and find files
  def self.discover_docs barclamp

    doc_path = File.join barclamp.source_path, 'doc'
    Rails.logger.debug("Discovering docs for #{barclamp.name} barclamp under #{doc_path}") 
    files_list = %x[find #{doc_path} -name *.md]
    files = files_list.split "\n"
    files = files.sort_by {|x| x.length} # to ensure that parents come before their children
    files.each do |file_name|

      name = file_name.sub(doc_path, '')

      # figure out order by inspecting name
      order = name[/\/([0-9]+)_[^\/]*$/,1]
      order = "9999" unless order
      order = order.to_s.rjust(6,'0') rescue "!error"

      # figure out title, the first markdown header in the file
      title = begin
                actual_title = File.open(file_name, 'r').readline
                # we require titles to star w/ # - anything else is considered extra content
                next unless actual_title.starts_with? "#"
                actual_title.strip[/^#+(.*?)#*$/,1].strip
              rescue
                Rails.logger.debug("Skipping file #{file_name}") 
                next  # if that fails, skip
              end

      # figure out parent by looking one level up in the path
      # If the parent isn't found, we create a placeholder entry, to cover 
      # instances where the corresponding 'parent_name.md' file doesn't exit
      # but a parent directory exists.
      # 
      parent_name = File.dirname name
      parent = Doc.find_by_name "#{parent_name}.md"  

      if not parent and parent_name != "/"
        # no parent, create a dummy parent entry
        grandparent_name = File.dirname File.dirname name
        # Rails.logger.debug("grandparent: #{grandparent_name}.md ") 
        grandparent = Doc.find_by_name  "#{grandparent_name}.md" 
        parent = Doc.create :name=>"#{parent_name}.md", 
          :description=> "placeholder for missing #{parent_name}".truncate(120),
          :order=>'009999', :parent_id=>(grandparent ? grandparent.id : nil),
          :barclamp_id =>barclamp.id
      end

      d = Doc.find_or_create_by_name :name=>name, 
        :description=>title.truncate(120),
        :order=>order, :parent_id=>(parent ? parent.id : nil), 
        :barclamp_id=>barclamp.id

    end
  end

  def level 
    name.count("/")-1
  end

  def git_url
    path = self.name.split '/'
    path[0] = "https://github.com/opencrowbar/#{barclamp.name}/tree/master/doc"
    return path.join('/')
  end


end

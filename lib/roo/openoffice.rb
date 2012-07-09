require 'rubygems'
require 'fileutils'
require 'zip/zipfilesystem'
require 'date'
require 'nokogiri'
require 'cgi'
require 'pp' #TODO
class Openoffice < GenericSpreadsheet

  @@nr = 0

  # initialization and opening of a spreadsheet file
  # values for packed: :zip
  def initialize(filename, packed=nil, file_warning=:error, tmpdir=nil)
    @file_warning = file_warning
    super()
    file_type_check(filename,'.ods','an openoffice', packed)
    @tmpdir = GenericSpreadsheet.next_tmpdir
    @tmpdir = File.join(ENV['ROO_TMP'], @tmpdir) if ENV['ROO_TMP'] 
    @tmpdir = File.join(tmpdir, @tmpdir) if tmpdir 
    unless File.exists?(@tmpdir)
      FileUtils::mkdir(@tmpdir)
    end
    filename = open_from_uri(filename) if filename[0,7] == "http://"
    filename = unzip(filename) if packed and packed == :zip
    @cells_read = Hash.new
    #TODO: @cells_read[:default] = false
    @filename = filename
    unless File.file?(@filename)
      FileUtils::rm_r(@tmpdir)
      raise IOError, "file #{@filename} does not exist"
    end
    @@nr += 1
    @file_nr = @@nr
    extract_content
    file = File.new(File.join(@tmpdir, @file_nr.to_s+"_roo_content.xml"))
    @doc = Nokogiri::XML(file)
    file.close
    FileUtils::rm_r(@tmpdir)
    @default_sheet = self.sheets.first
    @cell = Hash.new
    @cell_type = Hash.new
    @formula = Hash.new
    @first_row = Hash.new
    @last_row = Hash.new
    @first_column = Hash.new
    @last_column = Hash.new
    @style = Hash.new
    @style_defaults = Hash.new { |h,k| h[k] = [] }
    @style_definitions = Hash.new 
    @header_line = 1
    @label = Hash.new
    @labels_read = false
    @comment = Hash.new
    @comments_read = Hash.new
  end

  def method_missing(m,*args)
    read_labels unless @labels_read
    # is method name a label name
	  if @label.has_key?(m.to_s)
      row,col = label(m.to_s)
		  cell(row,col)
	  else
		  # call super for methods like #a1 
		  super
	  end
  end

  # Returns the content of a spreadsheet-cell.
  # (1,1) is the upper left corner.
  # (1,1), (1,'A'), ('A',1), ('a',1) all refers to the
  # cell at the first line and first row.
  def cell(row, col, sheet=nil)
    sheet = @default_sheet unless sheet
    read_cells(sheet) unless @cells_read[sheet]
    row,col = normalize(row,col)
    if celltype(row,col,sheet) == :date
      yyyy,mm,dd = @cell[sheet][[row,col]].to_s.split('-')
      return Date.new(yyyy.to_i,mm.to_i,dd.to_i)
    end
    @cell[sheet][[row,col]]
  end

  # Returns the formula at (row,col).
  # Returns nil if there is no formula.
  # The method #formula? checks if there is a formula.
  def formula(row,col,sheet=nil)
    sheet = @default_sheet unless sheet
    read_cells(sheet) unless @cells_read[sheet]
    row,col = normalize(row,col)
    if @formula[sheet][[row,col]] == nil
      return nil
    else
      # return @formula[sheet][[row,col]]["oooc:".length..-1]
      # TODO:
      #str = @formula[sheet][[row,col]]
      #if str.include? ':'
	      #return str[str.index(':')+1..-1]
      #else
	      #return str
      #end
      @formula[sheet][[row,col]]
    end
  end

  # true, if there is a formula
  def formula?(row,col,sheet=nil)
    sheet = @default_sheet unless sheet
    read_cells(sheet) unless @cells_read[sheet]
    row,col = normalize(row,col)
    formula(row,col) != nil
  end

  # returns each formula in the selected sheet as an array of elements
  # [row, col, formula]
  def formulas(sheet=nil)
    sheet = @default_sheet unless sheet
    read_cells(sheet) unless @cells_read[sheet]
    if @formula[sheet]
      @formula[sheet].each.collect do |elem|
        [elem[0][0], elem[0][1], elem[1]]
      end
    else
      []
    end
  end

  class Font
    attr_accessor :bold, :italic, :underline
    
    def bold? 
      @bold == 'bold'
    end

    def italic? 
      @italic == 'italic'
    end
    
    def underline? 
      @underline != nil
    end
  end

  # Given a cell, return the cell's style 
  def font(row, col, sheet=nil)
    sheet = @default_sheet unless sheet
    read_cells(sheet) unless @cells_read[sheet]
    row,col = normalize(row,col)
    style_name = @style[sheet][[row,col]] || @style_defaults[sheet][col - 1] || 'Default'
    @style_definitions[style_name]
  end 
  
  # set a cell to a certain value
  # (this will not be saved back to the spreadsheet file!)
  def set(row,col,value,sheet=nil) #:nodoc:
    sheet = @default_sheet unless sheet
    read_cells(sheet) unless @cells_read[sheet]
    row,col = normalize(row,col)
    set_value(row,col,value,sheet)
    if value.class == Fixnum
      set_type(row,col,:float,sheet)
    elsif value.class == String
      set_type(row,col,:string,sheet)
    elsif value.class == Float
      set_type(row,col,:string,sheet)
    else
      raise ArgumentError, "Type for "+value.to_s+" not set"
    end
  end

  # returns the type of a cell:
  # * :float
  # * :string
  # * :date
  # * :percentage
  # * :formula
  # * :time
  # * :datetime
  def celltype(row,col,sheet=nil)
    sheet = @default_sheet unless sheet
    read_cells(sheet) unless @cells_read[sheet]
    row,col = normalize(row,col)
    if @formula[sheet][[row,col]]
      return :formula
    else
      @cell_type[sheet][[row,col]]
    end
  end

  def sheets
    return_sheets = []
    @doc.xpath("//*[local-name()='table']").each do |sheet|
      return_sheets << sheet['name']
    end
    return_sheets
  end
    
  # version of the openoffice document
  # at 2007 this is always "1.0"
  def officeversion
    oo_version
    @officeversion
  end

  # shows the internal representation of all cells
  # mainly for debugging purposes
  def to_s(sheet=nil)
    sheet = @default_sheet unless sheet
    read_cells(sheet) unless @cells_read[sheet]
    @cell[sheet].inspect
  end

  # returns the row,col values of the labelled cell
  # (nil,nil) if label is not defined
  def label(labelname)
    read_labels unless @labels_read
    unless @label.size > 0
      return nil,nil,nil
    end
    if @label.has_key? labelname
      return @label[labelname][1].to_i,
        GenericSpreadsheet.letter_to_number(@label[labelname][2]),
        @label[labelname][0]
    else
      return nil,nil,nil
    end
  end

  # Returns an array which all labels. Each element is an array with
  # [labelname, [sheetname,row,col]]
  def labels(sheet=nil)
    read_labels unless @labels_read
    result = []
    @label.each do |label|
      result << [ label[0], # name
        [ label[1][1].to_i, # row
          GenericSpreadsheet.letter_to_number(label[1][2]), # column
          label[1][0], # sheet
        ] ]
    end
    result
  end

  # returns the comment at (row/col)
  # nil if there is no comment
  def comment(row,col,sheet=nil)
    sheet = @default_sheet unless sheet
    read_cells(sheet) unless @cells_read[sheet]
    row,col = normalize(row,col)
    return nil unless @comment[sheet]
    @comment[sheet][[row,col]]
  end

  # true, if there is a comment
  def comment?(row,col,sheet=nil)
    sheet = @default_sheet unless sheet
    read_cells(sheet) unless @cells_read[sheet]
    row,col = normalize(row,col)
    comment(row,col) != nil
  end


  # returns each comment in the selected sheet as an array of elements
  # [row, col, comment]
  def comments(sheet=nil)
    sheet = @default_sheet unless sheet
    read_comments(sheet) unless @comments_read[sheet]
    if @comment[sheet]
      @comment[sheet].each.collect do |elem|
        [elem[0][0],elem[0][1],elem[1]]
      end
    else
      []
    end
  end

  private

  # read the version of the OO-Version
  def oo_version
    @doc.xpath("//*[local-name()='document-content']").each do |office|
      @officeversion = office.attributes['version'].to_s
    end
  end

  # helper function to set the internal representation of cells
  def set_cell_values(sheet,x,y,i,v,vt,formula,table_cell,str_v,style_name)
    key = [y,x+i]    
    @cell_type[sheet] = {} unless @cell_type[sheet]
    @cell_type[sheet][key] = Openoffice.oo_type_2_roo_type(vt)
    @formula[sheet] = {} unless @formula[sheet]
    if formula
      ['of:', 'oooc:'].each do |prefix|
        if formula[0,prefix.length] == prefix
          formula = formula[prefix.length..-1]
        end
      end
      @formula[sheet][key] = formula
    end
    @cell[sheet] = {} unless @cell[sheet]
    @style[sheet] = {} unless @style[sheet]
    @style[sheet][key] = style_name
    case @cell_type[sheet][key]
    when :float
      @cell[sheet][key] = v.to_f
    when :string
      @cell[sheet][key] = str_v
    when :date
      #TODO: if table_cell.attributes['date-value'].size != "XXXX-XX-XX".size
      if table_cell.attributes['date-value'].to_s.size != "XXXX-XX-XX".size
        #-- dann ist noch eine Uhrzeit vorhanden
        #-- "1961-11-21T12:17:18"
        @cell[sheet][key] = DateTime.parse(table_cell.attributes['date-value'].to_s)
        @cell_type[sheet][key] = :datetime
      else
        @cell[sheet][key] = table_cell.attributes['date-value']
      end
    when :percentage
      @cell[sheet][key] = v.to_f
    when :time
      hms = v.split(':')
      @cell[sheet][key] = hms[0].to_i*3600 + hms[1].to_i*60 + hms[2].to_i
    else
      @cell[sheet][key] = v
    end
  end

  # read all cells in the selected sheet
  #--
  # the following construct means '4 blanks'
  # some content <text:s text:c="3"/>
  #++
  def read_cells(sheet=nil)
    sheet = @default_sheet unless sheet
    sheet_found = false
    raise ArgumentError, "Error: sheet '#{sheet||'nil'}' not valid" if @default_sheet == nil and sheet==nil
    raise RangeError unless self.sheets.include? sheet

    @doc.xpath("//*[local-name()='table']").each do |ws|
      if sheet == ws['name']
        sheet_found = true
        col = 1
        row = 1
        ws.children.each do |table_element|
          case table_element.name
          when 'table-column'
            @style_defaults[sheet] << table_element.attributes['default-cell-style-name'] 
          when 'table-row'
            if table_element.attributes['number-rows-repeated']
              skip_row = table_element.attributes['number-rows-repeated'].to_s.to_i
              row = row + skip_row - 1
            end
            table_element.children.each do |cell|
              skip_col = cell['number-columns-repeated']
              formula = cell['formula']
              vt = cell['value-type']
              v =  cell['value']
              style_name = cell['style-name']
              if vt == 'string'
                str_v  = ''
                # insert \n if there is more than one paragraph
                para_count = 0
                cell.children.each do |str|
                  # begin comments
=begin
- <table:table-cell office:value-type="string">
  - <office:annotation office:display="true" draw:style-name="gr1" draw:text-style-name="P1" svg:width="1.1413in" svg:height="0.3902in" svg:x="2.0142in" svg:y="0in" draw:caption-point-x="-0.2402in" draw:caption-point-y="0.5661in">
      <dc:date>2011-09-20T00:00:00</dc:date>
      <text:p text:style-name="P1">Kommentar fuer B4</text:p>
    </office:annotation>
    <text:p>B4 (mit Kommentar)</text:p>
  </table:table-cell>
=end
                  if str.name == 'annotation'
                    str.children.each do |annotation|
                      if annotation.name == 'p'
                        # @comment ist ein Hash mit Sheet als Key (wie bei @cell)
                        # innerhalb eines Elements besteht ein Eintrag aus einem
                        # weiteren Hash mit Key [row,col] und dem eigentlichen
                        # Kommentartext als Inhalt
                        @comment[sheet] = Hash.new unless @comment[sheet]
                        key = [row,col]
                        @comment[sheet][key] = annotation.text
                      end
                    end
                  end
                  # end comments
                  if str.name == 'p'
                    v = str.content
                    str_v += "\n" if para_count > 0
                    para_count += 1
                    if str.children.size > 1
                      str_v += children_to_string(str.children)
                    else
                      str.children.each do |child|
                        str_v += child.content #.text
                      end
                    end
                    str_v.gsub!(/&apos;/,"'")  # special case not supported by unescapeHTML
                    str_v = CGI.unescapeHTML(str_v)
                  end # == 'p'
                end
              elsif vt == 'time'
                cell.children.each do |str|
                  if str.name == 'p'
                    v = str.content
                  end
                end
              elsif vt == '' or vt == nil
                #
              elsif vt == 'date'
                #
              elsif vt == 'percentage'
                #
              elsif vt == 'float'
                #
              elsif vt == 'boolean'
                v = cell.attributes['boolean-value'].to_s
              else
                # raise "unknown type #{vt}"
              end
              if skip_col
                if v != nil or cell.attributes['date-value']
                  0.upto(skip_col.to_i-1) do |i|
                    set_cell_values(sheet,col,row,i,v,vt,formula,cell,str_v,style_name)
                  end
                end
                col += (skip_col.to_i - 1)
              end # if skip
              set_cell_values(sheet,col,row,0,v,vt,formula,cell,str_v,style_name)
              col += 1
            end
            row += 1
            col = 1
          end
        end
      end
    end
    @doc.xpath("//*[local-name()='automatic-styles']").each do |style|
      read_styles(style)
    end
    if !sheet_found
      raise RangeError
    end
    @cells_read[sheet] = true
    @comments_read[sheet] = true
  end

  # Only calls read_cells because GenericSpreadsheet calls read_comments
  # whereas the reading of comments is done in read_cells for Openoffice-objects
  def read_comments(sheet=nil)
    read_cells(sheet)
  end
  
  def read_labels
    @doc.xpath("//table:named-range").each do |ne|
      #-
      # $Sheet1.$C$5
      #+
      name = ne.attribute('name').to_s
      sheetname,coords = ne.attribute('cell-range-address').to_s.split('.')
      col = coords.split('$')[1]
      row = coords.split('$')[2]
      sheetname = sheetname[1..-1] if sheetname[0,1] == '$'
      @label[name] = [sheetname,row,col]
    end
    @labels_read = true
  end
  
  def read_styles(style_elements)
    @style_definitions['Default'] = Openoffice::Font.new
    style_elements.each do |style|
      next unless style.name == 'style'
      style_name = style.attributes['name']
      style.each do |properties|
        font = Openoffice::Font.new
        font.bold = properties.attributes['font-weight']
        font.italic = properties.attributes['font-style']
        font.underline = properties.attributes['text-underline-style']
        @style_definitions[style_name] = font
      end
    end
  end
  
  # Checks if the default_sheet exists. If not an RangeError exception is
  # raised
  def check_default_sheet
    sheet_found = false
    raise ArgumentError, "Error: default_sheet not set" if @default_sheet == nil
    sheet_found = true if sheets.include?(@default_sheet)
    if ! sheet_found
      raise RangeError, "sheet '#{@default_sheet}' not found"
    end
  end

  def process_zipfile(zip, path='')
    if zip.file.file? path
      if path == "content.xml"
        open(File.join(@tmpdir, @file_nr.to_s+'_roo_content.xml'),'wb') {|f|
          f << zip.read(path)
        }
      end
    else
      unless path.empty?
        path += '/'
      end
      zip.dir.foreach(path) do |filename|
        process_zipfile(zip, path+filename)
      end
    end
  end

  def extract_content
    Zip::ZipFile.open(@filename) do |zip|
      process_zipfile(zip)
    end
  end

  def set_value(row,col,value,sheet=nil)
    sheet = @default_value unless sheet
    @cell[sheet][[row,col]] = value
  end

  def set_type(row,col,type,sheet=nil)
    sheet = @default_value unless sheet
    @cell_type[sheet][[row,col]] = type
  end

  A_ROO_TYPE = {
    "float"      => :float,
    "string"     => :string,
    "date"       => :date,
    "percentage" => :percentage,
    "time"       => :time,
  }

  def Openoffice.oo_type_2_roo_type(ootype)
    return A_ROO_TYPE[ootype]
  end
 
  # helper method to convert compressed spaces and other elements within
  # an text into a string
  def children_to_string(children)
    result = ''
    children.each {|child|
      if child.text?
        result = result + child.content
      else
        if child.name == 's'
          compressed_spaces = child.attributes['c'].to_s.to_i
          # no explicit number means a count of 1:
          if compressed_spaces == 0
            compressed_spaces = 1
          end
          result = result + " "*compressed_spaces
        else
          result = result + child.content
        end
      end
    }
    result
  end

end # class

# Libreoffice is just an alias for Openoffice class
class Libreoffice < Openoffice
end

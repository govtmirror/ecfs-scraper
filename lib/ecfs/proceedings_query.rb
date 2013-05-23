require "mechanize"

module ECFS
  class ProceedingsQuery
    include ECFS::Query

    def constraints_dictionary
      {
        "docket_number"  => "name",
        "bureau_code"    => "bureauCode",
        "subject"        => "subject",
        "bureau_id"      => "bureauIdentificationNumber",
        "applicant"      => "application",
        "filed_by"       => "filedBy",
        "recent_filings" => "__checkbox_recentFilingsRequired",
        "open_status"    => "openStatus",
        "created_after"  => "created.minDate",
        "created_before" => "created.maxDate",
        "closed_after"   => "closed.minDate",
        "closed_before"  => "closed.maxDate",
        "callsign"       => "callsign",
        "channel"        => "channel",
        "rule_section"   => "ruleSection",
        "page_number"    => "pageNumber",
        "per_page"       => "pageSize"
      }
    end

    self.new.constraints_dictionary.keys.each do |key|
      class_eval do

        define_method("#{key}=") do |value|
          eq(key, value)
        end

        define_method(key) do
          @constraints[key]
        end

      end
    end

    def base_url
      "http://apps.fcc.gov/ecfs/proceeding_search/execute"
    end

    def get
      if @constraints["docket_number"]
        # if docket_number is given along with other constraints, the other constraints will be ignored.
        warn "Constraints other than `docket_number` will be ignored." if @constraints.keys.length > 1
        
        return scrape_proceedings_page unless @typecast_results
        results = ECFS::Proceeding.new(scrape_proceedings_page)
      else
        return scrape_results_page unless @typecast_results
        results = ECFS::Proceeding::ResultSet.new(scrape_results_page)
      end

      results
    end

    def mechanize_page
      Mechanize.new.get(self.url)
    end

    private

    def scrape_proceedings_page
      page = self.mechanize_page

      container = []
      page.search("div").select do |d| 
        d.attributes["class"].nil? == false
      end.select do |d|
        d.attributes["class"].text == "wwgrp"
      end.each do |node|
        node.search("span").each do |span|
          search = span.search("label")
          pair = []
          if search.length > 0
            key = search.first.children.first.text.lstrip.rstrip.split(":")[0].gsub(" ", "_").downcase
            pair << key
          else
            value = span.text.lstrip.rstrip
            value.gsub!(",", "") if value.is_a?(String)
            pair << value
          end
          container << pair
        end
      end
      hash = {}
      container.each_slice(2) do |chunk|
        hash.merge!({chunk[0][0] => chunk[1][0]})
      end

      hash
    end

    def scrape_results_page
      page = self.mechanize_page

      total_pages = page.link_with(:text => "Last").attributes.first[1].split("pageNumber=")[1].gsub(",","").to_i
      banner      = page.search("//*[@id='yui-main']/div/div[2]/table/tbody/tr[2]/td/span[1]").text.lstrip.rstrip.split("Modify Search")[0].rstrip.split  
      first       = banner[1].gsub(",","").to_i
      last        = banner[3].gsub(",","").to_i
      total       = banner[5].gsub(",","").to_i
      table_rows  = page.search("//*[@id='yui-main']/div/div[2]/table/tbody/tr[2]/td/table/tbody").children
      results     = table_rows.map { |row| row_to_proceeding(row) }

      {
        "constraints"   => @constraints,
        "fcc_url"       => self.url,
        "current_page"  => self.constraints["page_number"].gsub(",","").to_i,
        "total_pages"   => total_pages,
        "first_result"  => first,
        "last_result"   => last,
        "total_results" => total,
        "results"       => results
      }
    end

    def row_to_proceeding(row)
      hash = row_to_hash(row)

      ECFS::Proceeding.new(hash)
    end

    def row_to_hash(row)
      bureau        = bureau_from_row(row)
      subject       = subject_from_row(row)
      docket_number = docket_number_from_row(row)
      {
        "docket_number" => docket_number,
        "bureau"        => bureau,
        "subject"       => subject
      }
    end

    def bureau_from_row(row)
      row.children[2].children.children.first.text.lstrip.rstrip
    end

    def docket_number_from_row(row)
      row.children[0].children[1].attributes["href"].value.split("name=")[1].rstrip
    end

    def subject_from_row(row)
      row.children[4].children.text.lstrip.rstrip
    end

  end
end
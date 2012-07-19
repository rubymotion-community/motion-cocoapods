class MyTableViewController < UITableViewController
  BASE_URL = "http://json-lipsum.appspot.com"

  def viewDidLoad
    @json = {}
    loadData
  end

  def tableView(tableView, numberOfRowsInSection:section)
    @json.keys.count
  end

  def tableView(tableView, cellForRowAtIndexPath:indexPath)
    cell = tableView.dequeueReusableCellWithIdentifier("test") || UITableViewCell.alloc.initWithStyle(UITableViewCellStyleSubtitle, reuseIdentifier:"test")
    cell.textLabel.text =  @json.keys[indexPath.row]
    cell.detailTextLabel.text = @json.values[indexPath.row]
    cell
  end

   def request(request, didLoadResponse: response)
     @data = response.bodyAsString.dataUsingEncoding(NSUTF8StringEncoding)
     error_ptr = Pointer.new(:object)
     @json = NSJSONSerialization.JSONObjectWithData(@data, options:0, error:error_ptr)
     self.view.reloadData
   end

   def loadData
    @client = RKClient.clientWithBaseURLString(BASE_URL)
    @client.get("/?amount=5&what=words&start=no", delegate:self);
  end


end

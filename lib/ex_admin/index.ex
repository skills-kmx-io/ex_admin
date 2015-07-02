defmodule ExAdmin.Index do
  require Logger
  require Integer
  import ExAdmin.Utils
  import ExAdmin.DslUtils
  #import UcxCallout.Admin.ViewHelpers, only: [get_route_path: 3]
  import ExAdmin.Helpers
  import Kernel, except: [div: 2, to_string: 1]
  use Xain
  alias Phoenix.HTML.Link
  import Phoenix.HTML

  defmacro __using__(_) do
    quote do
      import unquote(__MODULE__)
    end
  end

  defmacro index(opts \\ [], do: block) do

    contents = quote do
      unquote(block)
    end

    quote location: :keep, bind_quoted: [opts: escape(opts), contents: escape(contents)] do
      def index_view(var!(conn), page) do
        var!(columns, ExAdmin.Show) = []
        var!(selectable_column, ExAdmin.Index) = nil
        unquote(contents)
        columns = var!(columns, ExAdmin.Show) |> Enum.reverse
        selectable = case var!(selectable_column, ExAdmin.Index) do
          nil -> false
          other -> other
        end
        markup do
          ExAdmin.Index.render_index_table(var!(conn), page, columns, %{selectable_column: selectable})
        end

      end
    end
  end
  
  defmacro selectable_column do
    quote do
      var!(selectable_column, ExAdmin.Index) = true
    end
  end

  defp get_resource_fields([]), do: []
  defp get_resource_fields([resource | _]), do: resource.__struct__.__schema__(:fields)

  def render_index_table(conn, page, columns, %{selectable_column: selectable}) do
    href = get_route_path(conn, :index) <> "?order="
    resources = page.entries
    fields = get_resource_fields resources
    count = ExAdmin.Query.count resources
    name = resource_name(conn) |> titleize |> Inflex.pluralize
    order = get_sort_order(conn.params["order"]) 
    defn = ExAdmin.get_registered_by_controller_route(conn.params["resource"])
    batch_actions = not false in defn.batch_actions
    selectable = selectable and batch_actions
    columns = unless Enum.any? columns, &((elem &1, 0) == "Actions") do
      columns ++ [{"Actions", %{fun: fn(resource) -> build_index_links(conn, resource) end}}]
    else
      columns
    end

    label = get_resource_label(conn) |> Inflex.pluralize
    resource_name = conn.params["resource"]

    batch_action_form batch_actions, resource_name, fn -> 
      if count == 0 do
        div ".blank_slate_container" do
          span ".blank_slate" do
            if conn.params["q"] do
              text "No #{humanize label} found."
            else
              text "There are no #{humanize label} yet. "
              if ExAdmin.has_action?(defn, :new) do
                a "Create one", href: get_route_path(conn, :new)
              end
            end
          end
        end
      else
        div ".paginated_collection" do
          div ".paginated_collection_contents" do
            div ".index_content" do
              div ".index_as_table" do
                table("#contacts.index_table.index", border: "0", cellspacing: "0", 
                    cellpadding: "0", paginator: "true") do
                  ExAdmin.Table.table_head(columns, %{selectable: true, path_prefix: href, 
                    sort: "desc", order: order, fields: fields, selectable_column: selectable})
                  build_table_body(conn, resources, columns, %{selectable_column: selectable})
                end # table          
              end
            end # .index_content
          end
          div "#index_footer" do
            ExAdmin.Paginate.paginate(href, page.page_number, page.page_size, page.total_pages, count, name)
            download_links(conn)
          end
        end
      end
    end
  end

  def batch_action_form enabled?, name, fun do
    msg = "Are you sure you want to delete these #{name}? You wont be able to undo this."
    if enabled? do
      form "#collection_selection", action: "/admin/#{name}/batch_action", method: :post, "accept-charset": "UTF-8" do
        div style: "margin:0;padding:0;display:inline" do
          input name: "utf8", type: :hidden, value: "✓"
        end
        input "#batch_action", name: "batch_action", type: :hidden
        div ".table_tools" do
          div "#batch_actions_selector.dropdown_menu" do
            a ".disabled.dropdown_menu_button Batch Actions", href: "#"
            div ".dropdown_menu_list_wrapper", style: "display: none;" do
              div ".dropdown_menu_nipple"
              ul ".dropdown_menu_list" do
                li do
                  a ".batch_action Delete Selected", href: "#", "data-action": :destroy, "data-confirm": msg
                end
              end
            end
          end
        end
        fun.()
      end
    else
      fun.()
    end
  end

  def download_links(conn) do
    div ".download_links Download: " do
      a "CSV", href: "#{get_route_path(conn, :index)}/csv"
    end
  end

  def parameterize(name, seperator \\ "_")
  def parameterize(atom, seperator) when is_atom(atom) do
    Atom.to_string(atom)
    |> parameterize(seperator)
  end
  def parameterize(string, seperator) do
    Inflex.parameterize(string, seperator)
  end

  # def build_table_head(conn, _resources, columns) do
  #   path_prefix = get_route_path(conn, :index) <> "?order="

  #   Logger.error "columns: #{inspect columns}"


  #   thead do
  #     tr do
  #       th(".selectable") do
  #         div(".resource_selection_toggle_cell") do
  #           input("#collection_selection_toggle_all.toggle_all", type: "checkbox", name: "collection_selection_toggle_all")
  #         end
  #       end
  #       for {field_name, opts} <- columns do 
  #         build_th field_name, path_prefix, "desc"
  #       end
  #       #th "Actions"
  #     end
  #   end
  # end

  # def build_th(field_name, path_prefix, sort) when is_binary(field_name) do
  #   th(class: to_class(field_name)) do
  #     text field_name
  #   end
  # end
  # def build_th(field_name, path_prefix, sort) when is_atom(field_name) do
  #   th(".sortable.#{field_name}") do
  #     a("#{humanize field_name}", href: path_prefix <> Atom.to_string(field_name) <> "_#{sort}")
  #   end
  # end

  def build_table_body(_conn, [], _columns, _opts) do
    tbody
  end
  def build_table_body(_conn, resources, columns, opts) do
    model_name = resources |> List.first |> Map.get(:__struct__)
    selectable = Map.get opts, :selectable_column

    tbody do
      Enum.with_index(resources) 
      |> Enum.map(fn{resource, inx} -> 
        odd_even = if Integer.is_even(inx), do: "even", else: "odd"
        id = resource.id
        tr(".#{odd_even}##{model_name}_#{id}") do
          if selectable do
            td(".selectable") do
              div(".resource_selection_cell") do
                input(".collection_selection#batch_action_item_#{id}", type: :checkbox, value: "#{id}",
                  name: "collection_selection[]")
              end
            end
          end

          for field <- columns do
            build_field(resource, field, fn(contents, field_name) -> 
              ExAdmin.Table.handle_contents(contents, field_name)
            end)
          end
        end # tr
      end)
    end
  end

  # TODO: don't like that we can't handle the do block :(

  def build_index_links(conn, resource) do
    # name = controller_name(conn)
    base_class = "member_link"
    id = resource.id
    [ Link.link("View", to: get_route_path(conn, :show, id), class: base_class <> " view_link"),
      Link.link("Edit", to: get_route_path(conn, :edit, id), class: base_class <> " edit_link"),
      Link.link("Delete", to: get_route_path(conn, :delete, id), 
          class: base_class <> " delete_link", "data-confirm": confirm_message, 
          "data-method": :delete, rel: :nofollow ) ] 
    |> safe_concat
    # a("View", href: get_route_path(conn, :show, id), class: base_class <> " view_link")
    # a("Edit", href: get_route_path(conn, :edit, id), class: base_class <> " edit_link")
    # a("Delete", href: get_route_path(conn, :delete, id), 
    #     class: base_class <> " delete_link", "data-confirm": confirm_message, 
    #     "data-method": :delete, rel: :nofollow )
  end
end
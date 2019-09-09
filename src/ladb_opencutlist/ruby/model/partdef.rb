module Ladb::OpenCutList

  require 'digest'

  class PartDef

    EDGE_YMIN = :ymin
    EDGE_YMAX = :ymax
    EDGE_XMIN = :xmin
    EDGE_XMAX = :xmax

    EDGES = [ PartDef::EDGE_YMIN, PartDef::EDGE_YMAX, PartDef::EDGE_XMIN, PartDef::EDGE_XMAX ]
    EDGES_Y = [ PartDef::EDGE_YMIN, PartDef::EDGE_YMAX ]
    EDGES_X = [ PartDef::EDGE_XMIN, PartDef::EDGE_XMAX ]

    attr_accessor :definition_id, :number, :saved_number, :name, :is_dynamic_attributes_name, :count, :scale, :cutting_size, :size, :material_name, :material_type, :material_origins, :cumulable, :orientation_locked_on_axis, :labels, :edge_count, :edge_pattern, :edge_material_names, :edge_std_dimensions, :edge_entity_ids, :edge_length_decrement, :edge_width_decrement, :auto_oriented, :not_aligned_on_axes, :layers, :final_area, :children_warning_count
    attr_reader :id, :edge_material_names, :edge_std_dimensions, :edge_errors, :entity_ids, :entity_serialized_paths, :entity_names, :contains_blank_entity_names, :children, :edge_materials, :edge_group_defs

    def initialize(id)
      @id = id
      @definition_id = ''
      @number = nil
      @saved_number = nil
      @name = ''
      @is_dynamic_attributes_name = false
      @count = 0
      @cutting_size = Size3d.new
      @size = Size3d.new
      @scale = Scale3d.new
      @material_name = ''
      @material_type = MaterialAttributes::TYPE_UNKNOW
      @material_origins = []
      @cumulable = DefinitionAttributes::CUMULABLE_NONE
      @orientation_locked_on_axis = false
      @labels = ''
      @edge_count = 0
      @edge_pattern = nil                 # A string from 0000 to 1111
      @edge_material_names = {}
      @edge_std_dimensions = {}
      @edge_length_decrement = 0
      @edge_width_decrement = 0
      @edge_entity_ids = {}
      @edge_errors = []
      @entity_ids = []                    # All unique entity ids (array count could be smaller than @count)
      @entity_serialized_paths = []       # All Serialized path to each entity (array count should be egals to @count)
      @entity_names = {}                  # All non empty entity instance names (key = name, value = count)
      @contains_blank_entity_names = false
      @auto_oriented = false
      @not_aligned_on_axes = false
      @layers = []
      @final_area = 0

      @children_warning_count = 0
      @children = []

      # Internal
      @edge_materials = {}
      @edge_group_defs = {}

    end

    # -----

    def self.generate_part_id(group_id, definition, instance_info, dynamic_attributes_name = false)

      # Uses name for dynamic components to separate instances with the same definition, but different name
      entity_id = definition.entityID
      if dynamic_attributes_name
        name, is_dynamic_attributes_name = instance_info.read_name(dynamic_attributes_name)
        entity_id = name if is_dynamic_attributes_name
      end

      # Include size into part_id to separate instances with the same definition, but different scale
      Digest::MD5.hexdigest("#{group_id}|#{entity_id}|#{instance_info.size.length.to_s}|#{instance_info.size.width.to_s}|#{instance_info.size.thickness.to_s}")

    end

    def self.part_order(part_def_a, part_def_b, strategy)
      a_values = []
      b_values = []
      if strategy
        properties = strategy.split('>')
        properties.each { |property|
          if property.length < 1
            next
          end
          asc = true
          if property.start_with?('-')
            asc = false
            property.slice!(0)
          end
          case property
            when 'length'
              a_value = [ part_def_a.cumulative_cutting_length ]
              b_value = [ part_def_b.cumulative_cutting_length ]
            when 'width'
              a_value = [ part_def_a.cumulative_cutting_width ]
              b_value = [ part_def_b.cumulative_cutting_width ]
            when 'thickness'
              a_value = [ part_def_a.size.thickness ]
              b_value = [ part_def_b.size.thickness ]
            when 'name'
              a_value = [ part_def_a.name.downcase ]
              b_value = [ part_def_b.name.downcase ]
            when 'count'
              a_value = [ part_def_a.count ]
              b_value = [ part_def_b.count ]
            when 'edge_pattern'
              a_value = [ part_def_a.edge_count, part_def_a.edge_pattern.nil? ? '' : part_def_a.edge_pattern ]
              b_value = [ part_def_b.edge_count, part_def_b.edge_pattern.nil? ? '' : part_def_b.edge_pattern ]
            else
              next
          end
          if asc
            a_values.concat(a_value)
            b_values.concat(b_value)
          else
            a_values.concat(b_value)
            b_values.concat(a_value)
          end
        }
      end
      a_values <=> b_values
    end

    # -----

    def cumulative_cutting_length
      if @count > 1 && @cumulable == DefinitionAttributes::CUMULABLE_LENGTH
        (@cutting_size.length.to_f * @count).to_l
      else
        @cutting_size.length
      end
    end

    def cumulative_cutting_width
      if @count > 1 && @cumulable == DefinitionAttributes::CUMULABLE_WIDTH
        (@cutting_size.width.to_f * @count).to_l
      else
        @cutting_size.width
      end
    end

    def add_material_origin(material_origin)
      unless @material_origins.include? material_origin
        @material_origins.push(material_origin)
      end
    end

    def add_entity_id(entity_id)
      unless @entity_ids.include? entity_id   # Because of groups and components, multiple entity can have the same ID
        @entity_ids.push(entity_id)
      end
    end

    def add_entity_serialized_path(entity_serialized_path)
      @entity_serialized_paths.push(entity_serialized_path)
    end

    def add_entity_name(entity_name)
      if entity_name.empty?
        @contains_blank_entity_names = true
      else
        if @entity_names.has_key? entity_name
          @entity_names[entity_name] += 1
        else
          @entity_names[entity_name] = 1
        end
      end
    end

    def multiple_layers
      @layers.length > 1
    end

    def set_edge_materials(edge_ymin_material, edge_ymax_material, edge_xmin_material, edge_xmax_material)

      # Store materials internaly
      @edge_materials.store(PartDef::EDGE_YMIN, edge_ymin_material) unless edge_ymin_material.nil?
      @edge_materials.store(PartDef::EDGE_YMAX, edge_ymax_material) unless edge_ymax_material.nil?
      @edge_materials.store(PartDef::EDGE_XMIN, edge_xmin_material) unless edge_xmin_material.nil?
      @edge_materials.store(PartDef::EDGE_XMAX, edge_xmax_material) unless edge_xmax_material.nil?

      # Store material names
      @edge_material_names.store(PartDef::EDGE_YMIN, edge_ymin_material.name) unless edge_ymin_material.nil?
      @edge_material_names.store(PartDef::EDGE_YMAX, edge_ymax_material.name) unless edge_ymax_material.nil?
      @edge_material_names.store(PartDef::EDGE_XMIN, edge_xmin_material.name) unless edge_xmin_material.nil?
      @edge_material_names.store(PartDef::EDGE_XMAX, edge_xmax_material.name) unless edge_xmax_material.nil?

      # Compute edge count
      @edge_count = [ edge_ymin_material, edge_ymax_material, edge_xmin_material, edge_xmax_material ].select { |m| !m.nil? }.length

      # Bluid edge pattern
      @edge_pattern = "#{edge_ymin_material ? 1 : 0}#{edge_xmax_material ? 1 : 0}#{edge_ymax_material ? 1 : 0}#{edge_xmin_material ? 1 : 0}"

    end

    def set_edge_entity_ids(edge_ymin_entity_ids, edge_ymax_entity_ids, edge_xmin_entity_ids, edge_xmax_entity_ids)

      # Store materials internaly
      @edge_entity_ids.store(PartDef::EDGE_YMIN, edge_ymin_entity_ids) unless edge_ymin_entity_ids.nil?
      @edge_entity_ids.store(PartDef::EDGE_YMAX, edge_ymax_entity_ids) unless edge_ymax_entity_ids.nil?
      @edge_entity_ids.store(PartDef::EDGE_XMIN, edge_xmin_entity_ids) unless edge_xmin_entity_ids.nil?
      @edge_entity_ids.store(PartDef::EDGE_XMAX, edge_xmax_entity_ids) unless edge_xmax_entity_ids.nil?

    end

    def set_edge_group_defs(edge_ymin_group_def, edge_ymax_group_def, edge_xmin_group_def, edge_xmax_group_def)

      # Store groupDefs internaly
      @edge_group_defs.store(PartDef::EDGE_YMIN, edge_ymin_group_def) unless edge_ymin_group_def.nil?
      @edge_group_defs.store(PartDef::EDGE_YMAX, edge_ymax_group_def) unless edge_ymax_group_def.nil?
      @edge_group_defs.store(PartDef::EDGE_XMIN, edge_xmin_group_def) unless edge_xmin_group_def.nil?
      @edge_group_defs.store(PartDef::EDGE_XMAX, edge_xmax_group_def) unless edge_xmax_group_def.nil?

      # Store stdDimensions
      @edge_std_dimensions.store(PartDef::EDGE_YMIN, edge_ymin_group_def.std_dimension) unless edge_ymin_group_def.nil?
      @edge_std_dimensions.store(PartDef::EDGE_YMAX, edge_ymax_group_def.std_dimension) unless edge_ymax_group_def.nil?
      @edge_std_dimensions.store(PartDef::EDGE_XMIN, edge_xmin_group_def.std_dimension) unless edge_xmin_group_def.nil?
      @edge_std_dimensions.store(PartDef::EDGE_XMAX, edge_xmax_group_def.std_dimension) unless edge_xmax_group_def.nil?

    end

    # -----

    def to_struct(part_number)
      if @children.empty?
        {
            :id => @id,
            :definition_id => @definition_id,
            :name => @name,
            :is_dynamic_attributes_name => @is_dynamic_attributes_name,
            :resized => !@scale.identity?,
            :length => [@size.length - @edge_length_decrement, 0].max.to_l.to_s,
            :width => [@size.width - @edge_width_decrement, 0].max.to_l.to_s,
            :thickness => @size.thickness.to_s,
            :count => @count,
            :cutting_length => [@cutting_size.length - @edge_length_decrement, 0].max.to_l.to_s,
            :cutting_width => [@cutting_size.width - @edge_width_decrement].max.to_l.to_s,
            :cutting_thickness => @cutting_size.thickness.to_s,
            :cumulative_cutting_length => cumulative_cutting_length.to_s,
            :cumulative_cutting_width => cumulative_cutting_width.to_s,
            :number => @number ? @number : part_number,
            :saved_number => @saved_number,
            :material_name => @material_name,
            :material_type => @material_type,
            :material_origins => @material_origins,
            :cumulable => @cumulable,
            :orientation_locked_on_axis => @orientation_locked_on_axis,
            :labels => @labels,
            :entity_ids => @entity_ids,
            :entity_serialized_paths => @entity_serialized_paths,
            :entity_names => @entity_names.sort,
            :contains_blank_entity_names => @contains_blank_entity_names,
            :auto_oriented => @auto_oriented,
            :not_aligned_on_axes => @not_aligned_on_axes,
            :layers => @layers.map(&:name),
            :multiple_layers => multiple_layers,
            :edge_count => @edge_count,
            :edge_pattern => @edge_pattern,
            :edge_material_names => @edge_material_names,
            :edge_std_dimensions => @edge_std_dimensions,
            :edge_entity_ids => @edge_entity_ids,
            :edge_decrements => { :length => @edge_length_decrement > 0 ? @edge_length_decrement.to_s : nil, :width => @edge_width_decrement > 0 ? @edge_width_decrement.to_s : nil },
            :final_area => @final_area == 0 ? nil : DimensionUtils.instance.format_to_readable_area(@final_area),
            :normals_to_dimensions => @size.normals_to_dimensions,
            :l_ratio => @size.length / [@size.length, @size.width].max,
            :w_ratio => @size.width / [@size.length, @size.width].max,
        }
      else
        {
            :id => @id,
            :length => [@size.length - @edge_length_decrement, 0].max.to_l.to_s,
            :width => [@size.width - @edge_width_decrement, 0].max.to_l.to_s,
            :thickness => @size.thickness.to_s,
            :count => @count,
            :cutting_length => [@cutting_size.length - @edge_length_decrement, 0].max.to_l.to_s,
            :cutting_width => [@cutting_size.width - @edge_width_decrement].max.to_l.to_s,
            :cutting_thickness => @cutting_size.thickness.to_s,
            :saved_number => nil,
            :material_name => @material_name,
            :labels => @labels,
            :edge_pattern => @edge_pattern,
            :edge_material_names => @edge_material_names,
            :edge_std_dimensions => @edge_std_dimensions,
            :edge_decrements => { :length => @edge_length_decrement > 0 ? @edge_length_decrement.to_s : nil, :width => @edge_width_decrement > 0 ? @edge_width_decrement.to_s : nil },
            :final_area =>  @final_area == 0 ? nil : DimensionUtils.instance.format_to_readable_area(@final_area),
            :children_warning_count => @children_warning_count,
            :children => []
        }
      end
    end

  end

end
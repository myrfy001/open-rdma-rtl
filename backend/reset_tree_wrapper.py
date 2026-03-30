#!/usr/bin/env python3
"""
Verilog Module Reset Tree Wrapper Script

This script wraps a Verilog module to add two-stage register buffer
for the reset signal (RST_N).

Supports both standard Verilog and Bluespec Compiler generated Verilog.

Usage: python reset_tree_wrapper.py <input_verilog_file>
"""

import sys
import os
import re
import argparse


def parse_verilog_module(content):
    """Parse Verilog module to extract module name, parameters, ports, and body."""

    # Remove comments (both single-line and multi-line)
    content_no_comments = re.sub(r'//.*?$', '', content, flags=re.MULTILINE)
    content_no_comments = re.sub(r'/\*.*?\*/', '', content_no_comments, flags=re.DOTALL)

    # Find module declaration - try Bluespec format first
    # Bluespec format: module name(port1,
    #                               port2,
    #                               ...
    #                               portN);
    bs_pattern = r'module\s+(\w+)\s*\((.*?)\)\s*;'

    match = re.search(bs_pattern, content_no_comments, re.DOTALL)
    if not match:
        raise ValueError("Could not parse module declaration")

    original_name = match.group(1)
    ports_str = match.group(2)

    # Extract port names from module declaration (Bluespec style - just names)
    port_names_in_decl = []
    for line in ports_str.split('\n'):
        line = line.strip().rstrip(',')
        if line and not line.startswith('//'):
            # Handle multiple ports on same line separated by comma
            for port in line.split(','):
                port = port.strip()
                if port and re.match(r'^\w+$', port):
                    port_names_in_decl.append(port)

    # Find port declarations after module declaration
    # These contain the actual direction and width info
    module_end_match = content_no_comments.find(';', match.end())
    if module_end_match == -1:
        module_end_match = match.end()

    # Find all port declarations (input/output/inout)
    port_declarations = []
    port_decl_pattern = r'(input|output|inout)\s+(?:wire\s+)?(?:reg\s+)?(?:\[(\d+)\s*:\s*(\d+)\]\s+)?(\w+)\s*;'

    for m in re.finditer(port_decl_pattern, content_no_comments):
        direction = m.group(1)
        msb = m.group(2)
        lsb = m.group(3)
        name = m.group(4)

        width = None
        if msb is not None and lsb is not None:
            width = (int(msb), int(lsb))

        port_declarations.append({
            'direction': direction,
            'type': None,  # Bluespec doesn't use wire/reg in port declarations
            'width': width,
            'name': name
        })

    # Check if there are parameters
    parameters = []
    # Look for parameter declarations before or in module
    param_pattern = r'parameter\s+(?:\[\s*\d+\s*:\s*\d+\s*\]\s+)?(\w+)\s*=\s*([^;,]+)'
    for m in re.finditer(param_pattern, content_no_comments):
        param_name = m.group(1)
        param_value = m.group(2).strip()
        # Only include if it's likely a module parameter (before first always block)
        if 'always' not in content_no_comments[:m.start()]:
            parameters.append((param_name, param_value))

    # If no port declarations found, try standard Verilog format
    if not port_declarations:
        port_declarations = parse_standard_verilog_ports(ports_str)

    return {
        'name': original_name,
        'parameters': parameters,
        'ports': port_declarations,
        'full_match': match,
        'content': content
    }


def parse_standard_verilog_ports(ports_str):
    """Parse ports in standard Verilog format (direction in module declaration)."""
    ports = []

    # Split by comma, respecting nested brackets
    port_list = split_port_list(ports_str)

    for port_decl in port_list:
        port_decl = port_decl.strip()
        if not port_decl:
            continue

        port_info = parse_port_declaration(port_decl)
        if port_info:
            ports.append(port_info)

    return ports


def split_port_list(ports_str):
    """Split port list by commas, respecting nested brackets."""
    ports = []
    current = ""
    bracket_depth = 0

    for char in ports_str:
        if char == '[':
            bracket_depth += 1
            current += char
        elif char == ']':
            bracket_depth -= 1
            current += char
        elif char == ',' and bracket_depth == 0:
            ports.append(current.strip())
            current = ""
        else:
            current += char

    if current.strip():
        ports.append(current.strip())

    return ports


def parse_port_declaration(port_decl):
    """Parse a single port declaration."""

    # Pattern to match port with optional width
    pattern = r'^\s*(input|output|inout)\s+(?:(wire|reg)\s+)?(?:\[\s*(\d+)\s*:\s*(\d+)\s*\]\s+)?(\w+)\s*$'

    match = re.match(pattern, port_decl)
    if match:
        direction = match.group(1)
        port_type = match.group(2)
        msb = match.group(3)
        lsb = match.group(4)
        name = match.group(5)

        width = None
        if msb is not None and lsb is not None:
            width = (int(msb), int(lsb))

        return {
            'direction': direction,
            'type': port_type,
            'width': width,
            'name': name
        }

    return None


def generate_inner_module_content(original_content, original_name, new_name):
    """Generate the content for the inner module file (renamed module)."""
    # Replace module name in the declaration
    new_content = re.sub(
        r'module\s+' + re.escape(original_name) + r'\b',
        f'module {new_name}',
        original_content,
        count=1
    )
    return new_content


def generate_wrapper_module(original_name, inner_name, parameters, ports):
    """Generate the wrapper module with reset tree."""

    lines = []

    # Module declaration - Bluespec style (port names on separate lines)
    lines.append(f"module {original_name}(")

    # Add port names (Bluespec style - one per line with proper indentation)
    for i, port in enumerate(ports):
        if i == len(ports) - 1:
            # Last port - no comma, close parenthesis
            lines.append(f"\t\t {port['name']});")
        else:
            lines.append(f"\t\t {port['name']},")

    lines.append("")

    # Add port declarations (input/output with widths)
    for port in ports:
        port_str = f"  {port['direction']}"
        if port['width']:
            port_str += f"  [{port['width'][0]} : {port['width'][1]}]"
        port_str += f" {port['name']};"
        lines.append(port_str)

    lines.append("")

    # Add internal signals for reset tree
    lines.append("  // Reset tree registers")
    lines.append("  reg rst_n_d1;")
    lines.append("  reg rst_n_d2;")
    lines.append("")
    lines.append("  // Reset tree logic - two stage registers")
    lines.append("  always @(posedge CLK) begin")
    lines.append("    if (!RST_N) begin")
    lines.append("      rst_n_d1 <= 1'b0;")
    lines.append("      rst_n_d2 <= 1'b0;")
    lines.append("    end else begin")
    lines.append("      rst_n_d1 <= 1'b1;")
    lines.append("      rst_n_d2 <= rst_n_d1;")
    lines.append("    end")
    lines.append("  end")
    lines.append("")

    # Instance of inner module
    lines.append(f"  // Instance of inner module")
    instance_line = f"  {inner_name}"

    # Add parameter passing if any
    if parameters:
        instance_line += " #("
        param_pass_lines = []
        for param_name, _ in parameters:
            param_pass_lines.append(f"      .{param_name}({param_name})")
        instance_line += "\n" + ",\n".join(param_pass_lines) + "\n  )"

    instance_line += f" u_{inner_name} ("
    lines.append(instance_line)

    # Add port connections
    connection_lines = []
    for port in ports:
        port_name = port['name']
        if port_name == "RST_N":
            # Use the buffered reset
            connection_lines.append(f"    .{port_name}(rst_n_d2)")
        else:
            connection_lines.append(f"    .{port_name}({port_name})")

    lines.append(",\n".join(connection_lines))
    lines.append("  );")
    lines.append("")
    lines.append("endmodule")

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(
        description='Wrap a Verilog module with reset tree for RST_N signal.'
    )
    parser.add_argument('input_file', help='Path to the input Verilog file')
    parser.add_argument('--dry-run', action='store_true',
                        help='Show what would be done without making changes')

    args = parser.parse_args()

    input_path = args.input_file

    # Check file exists
    if not os.path.exists(input_path):
        print(f"Error: File not found: {input_path}")
        sys.exit(1)

    # Extract original name from filename
    filename = os.path.basename(input_path)
    if not filename.endswith('.v'):
        print(f"Error: File must have .v extension: {filename}")
        sys.exit(1)

    original_name = filename[:-2]  # Remove .v extension
    inner_name = f"{original_name}_reset_tree_inner"

    print(f"Original module name: {original_name}")
    print(f"Inner module name: {inner_name}")

    # Read original file
    with open(input_path, 'r', encoding='utf-8') as f:
        original_content = f.read()

    # Parse the module
    try:
        module_info = parse_verilog_module(original_content)
    except ValueError as e:
        print(f"Error parsing module: {e}")
        sys.exit(1)

    # Verify module name matches filename
    if module_info['name'] != original_name:
        print(f"Warning: Module name '{module_info['name']}' doesn't match filename '{original_name}'")
        print(f"Using module name from file: {module_info['name']}")
        original_name = module_info['name']
        inner_name = f"{original_name}_reset_tree_inner"

    print(f"Parameters found: {len(module_info['parameters'])}")
    print(f"Ports found: {len(module_info['ports'])}")

    if not module_info['ports']:
        print("Error: No ports found in module")
        sys.exit(1)

    # Show some port names for verification
    print(f"Sample ports: {[p['name'] for p in module_info['ports'][:5]]}")

    # Generate inner module content
    inner_content = generate_inner_module_content(
        original_content, original_name, inner_name
    )

    # Generate wrapper module content
    wrapper_content = generate_wrapper_module(
        original_name, inner_name,
        module_info['parameters'], module_info['ports']
    )

    # Get directory of input file
    dir_path = os.path.dirname(input_path)
    if not dir_path:
        dir_path = '.'
    inner_file_path = os.path.join(dir_path, f"{inner_name}.v")
    wrapper_file_path = os.path.join(dir_path, f"{original_name}.v")

    if args.dry_run:
        print("\n=== DRY RUN - No changes will be made ===")
        print(f"\nWould create inner file: {inner_file_path}")
        print(f"Would create wrapper file: {wrapper_file_path}")
        print("\n--- Wrapper Module Content Preview ---")
        # Show first 100 lines
        wrapper_lines = wrapper_content.split('\n')
        if len(wrapper_lines) > 100:
            print('\n'.join(wrapper_lines[:100]))
            print(f"... ({len(wrapper_lines) - 100} more lines)")
        else:
            print(wrapper_content)
        return

    # Check if inner file already exists
    if os.path.exists(inner_file_path) and inner_file_path != input_path:
        response = input(f"File {inner_file_path} already exists. Overwrite? (y/n): ")
        if response.lower() != 'y':
            print("Aborted.")
            sys.exit(0)

    # Rename original file to inner file (if not already named that way)
    if input_path != inner_file_path:
        print(f"Renaming {input_path} -> {inner_file_path}")
        os.rename(input_path, inner_file_path)

    # Write inner module content (with updated module name)
    with open(inner_file_path, 'w', encoding='utf-8') as f:
        f.write(inner_content)
    print(f"Updated module name in {inner_file_path}")

    # Create wrapper file
    with open(wrapper_file_path, 'w', encoding='utf-8') as f:
        f.write(wrapper_content)
    print(f"Created wrapper file: {wrapper_file_path}")

    print("\nDone!")
    print(f"  Inner module: {inner_file_path}")
    print(f"  Wrapper module: {wrapper_file_path}")


if __name__ == "__main__":
    main()

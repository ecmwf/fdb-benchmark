#!/usr/bin/env python3
"""
Convert README.md to a styled HTML file suitable for printing to PDF.
"""

import os
import markdown

def convert_markdown_to_html(md_file_path, html_file_path):
    """Convert markdown to HTML with print-friendly styling."""
    
    # Read the markdown file
    with open(md_file_path, 'r', encoding='utf-8') as f:
        md_content = f.read()
    
    # Convert markdown to HTML
    md = markdown.Markdown(extensions=['extra', 'codehilite', 'toc'])
    html_content = md.convert(md_content)
    
    # Create a complete HTML document with print-friendly CSS
    full_html = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>FDB Benchmark Documentation</title>
    <style>
        /* Print-friendly CSS */
        @media print {{
            body {{
                font-size: 12pt;
                line-height: 1.4;
                color: black;
                background: white;
                margin: 0.5in;
            }}
            h1, h2, h3, h4, h5, h6 {{
                break-after: avoid;
                page-break-after: avoid;
                color: #2c3e50;
            }}
            h1 {{
                font-size: 20pt;
                border-bottom: 2pt solid #3498db;
                padding-bottom: 8pt;
                margin-bottom: 12pt;
            }}
            h2 {{
                font-size: 16pt;
                border-bottom: 1pt solid #ecf0f1;
                padding-bottom: 4pt;
                margin-top: 16pt;
                margin-bottom: 8pt;
            }}
            h3 {{
                font-size: 14pt;
                margin-top: 12pt;
                margin-bottom: 6pt;
            }}
            pre, code {{
                font-size: 9pt;
                font-family: 'Courier New', Courier, monospace;
                background: #f8f9fa !important;
                border: 1pt solid #dee2e6;
                padding: 4pt;
                break-inside: avoid;
                page-break-inside: avoid;
            }}
            pre {{
                padding: 8pt;
                margin: 8pt 0;
                overflow: visible;
                white-space: pre-wrap;
                word-wrap: break-word;
            }}
            table {{
                break-inside: avoid;
                border-collapse: collapse;
                width: 100%;
                font-size: 11pt;
                margin: 8pt 0;
            }}
            th, td {{
                border: 1pt solid #dee2e6;
                padding: 4pt 6pt;
                text-align: left;
                vertical-align: top;
            }}
            th {{
                background-color: #f8f9fa;
                font-weight: bold;
            }}
            ul, ol {{
                margin: 6pt 0;
                padding-left: 20pt;
            }}
            li {{
                margin: 3pt 0;
            }}
            p {{
                margin: 6pt 0;
                line-height: 1.4;
            }}
            blockquote {{
                border-left: 2pt solid #3498db;
                margin: 8pt 0;
                padding-left: 8pt;
                font-style: italic;
            }}
            .print-instructions {{
                display: none;
            }}
        }}
        
        /* Screen CSS */
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            line-height: 1.6;
            color: #333;
            max-width: 900px;
            margin: 0 auto;
            padding: 20px;
            background: #fff;
        }}
        
        h1, h2, h3, h4, h5, h6 {{
            color: #2c3e50;
            margin-top: 1.5em;
            margin-bottom: 0.5em;
        }}
        
        h1 {{
            border-bottom: 3px solid #3498db;
            padding-bottom: 10px;
            font-size: 2.2em;
        }}
        
        h2 {{
            border-bottom: 2px solid #ecf0f1;
            padding-bottom: 5px;
            font-size: 1.8em;
        }}
        
        h3 {{
            font-size: 1.4em;
        }}
        
        code {{
            background: #f8f9fa;
            padding: 2px 5px;
            border-radius: 3px;
            font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', Courier, monospace;
            font-size: 0.9em;
        }}
        
        pre {{
            background: #f8f9fa;
            border: 1px solid #e9ecef;
            border-radius: 5px;
            padding: 15px;
            overflow-x: auto;
            font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', Courier, monospace;
            font-size: 0.85em;
            line-height: 1.4;
        }}
        
        pre code {{
            background: none;
            padding: 0;
            border-radius: 0;
        }}
        
        table {{
            border-collapse: collapse;
            width: 100%;
            margin: 1em 0;
        }}
        
        th, td {{
            border: 1px solid #ddd;
            padding: 12px;
            text-align: left;
        }}
        
        th {{
            background-color: #f2f2f2;
            font-weight: bold;
        }}
        
        tr:nth-child(even) {{
            background-color: #f9f9f9;
        }}
        
        blockquote {{
            border-left: 4px solid #3498db;
            margin: 1em 0;
            padding-left: 1em;
            color: #666;
        }}
        
        ul, ol {{
            padding-left: 2em;
        }}
        
        li {{
            margin: 0.5em 0;
        }}
        
        a {{
            color: #3498db;
            text-decoration: none;
        }}
        
        a:hover {{
            text-decoration: underline;
        }}
        
        .toc {{
            background: #f8f9fa;
            border: 1px solid #e9ecef;
            border-radius: 5px;
            padding: 15px;
            margin: 20px 0;
        }}
        
        .print-instructions {{
            background: #fff3cd;
            border: 1px solid #ffeaa7;
            border-radius: 5px;
            padding: 15px;
            margin: 20px 0;
        }}
    </style>
</head>
<body>
    <div class="print-instructions">
        <h3>📄 PDF Generation Instructions</h3>
        <p><strong>To create README.pdf:</strong></p>
        <ol>
            <li>Use your browser's Print function (Cmd+P on macOS, Ctrl+P on Windows/Linux)</li>
            <li>Select "Save as PDF" as the destination</li>
            <li>Choose "More settings" and ensure "Headers and footers" is unchecked</li>
            <li>Set margins to "Minimum" for better content fit</li>
            <li>Save as "README.pdf" in the project directory</li>
        </ol>
        <p><em>This instruction box will not appear in the printed PDF.</em></p>
    </div>
    
{html_content}
</body>
</html>"""
    
    # Write the HTML file
    with open(html_file_path, 'w', encoding='utf-8') as f:
        f.write(full_html)
    
    print(f"Successfully converted {md_file_path} to {html_file_path}")
    return html_file_path

def main():
    # Define file paths
    script_dir = os.path.dirname(os.path.abspath(__file__))
    md_file = os.path.join(script_dir, 'README.md')
    html_file = os.path.join(script_dir, 'README.html')
    
    # Check if README.md exists
    if not os.path.exists(md_file):
        print(f"Error: {md_file} not found!")
        return 1
    
    try:
        # Convert markdown to HTML
        print(f"Converting {md_file} to {html_file}...")
        convert_markdown_to_html(md_file, html_file)
        
        print("\n✅ Conversion completed successfully!")
        print(f"📁 HTML file created: {html_file}")
        print("\n📋 Next steps:")
        print("1. Open README.html in your browser")
        print("2. Use Print (Cmd+P) and select 'Save as PDF'")
        print("3. Save as 'README.pdf' in the project directory")
        
        return 0
        
    except Exception as e:
        print(f"Error during conversion: {e}")
        return 1

if __name__ == "__main__":
    exit(main())
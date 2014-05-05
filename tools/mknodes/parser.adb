------------------------------------------------------------------------------
--                                                                          --
--                           OCARINA COMPONENTS                             --
--                                                                          --
--                               P A R S E R                                --
--                                                                          --
--                                 B o d y                                  --
--                                                                          --
--    Copyright (C) 2005-2009 Telecom ParisTech, 2010-2014 ESA & ISAE.      --
--                                                                          --
-- Ocarina  is free software;  you  can  redistribute  it and/or  modify    --
-- it under terms of the GNU General Public License as published by the     --
-- Free Software Foundation; either version 2, or (at your option) any      --
-- later version. Ocarina is distributed  in  the  hope  that it will be    --
-- useful, but WITHOUT ANY WARRANTY;  without even the implied warranty of  --
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General --
-- Public License for more details. You should have received  a copy of the --
-- GNU General Public License distributed with Ocarina; see file COPYING.   --
-- If not, write to the Free Software Foundation, 51 Franklin Street, Fifth --
-- Floor, Boston, MA 02111-1301, USA.                                       --
--                                                                          --
-- As a special exception,  if other files  instantiate  generics from this --
-- unit, or you link  this unit with other files  to produce an executable, --
-- this  unit  does not  by itself cause  the resulting  executable to be   --
-- covered  by the  GNU  General  Public  License. This exception does not  --
-- however invalidate  any other reasons why the executable file might be   --
-- covered by the GNU Public License.                                       --
--                                                                          --
--                 Ocarina is maintained by the TASTE project               --
--                      (taste-users@lists.tuxfamily.org)                   --
--                                                                          --
------------------------------------------------------------------------------

with GNAT.Command_Line;
with GNAT.OS_Lib; use type GNAT.OS_Lib.File_Descriptor;

with Errors;
with Lexer; use type Lexer.Token_Type;
with Ocarina.Namet;
with Ocarina.Output; use Ocarina.Output;

with Ocarina.Types; use Ocarina.Types;

package body Parser is

   Debug     : Boolean := False;
   --  Provide debugging info from mknodes

   Dump_Tree : Boolean := True;
   --  Include full code to dump node tree

   Output_Dir  : Name_Id := No_Name;
   --  Directory storing generated files

   Output_Name : Name_Id := No_Name;
   --  File name of the output file

   Output_File : GNAT.OS_Lib.File_Descriptor := GNAT.OS_Lib.Invalid_FD;
   --  File descriptor storing generated code

   Source_Name : Name_Id;
   --  File name of the source file

   Source_File : GNAT.OS_Lib.File_Descriptor;
   --  File descriptor of the source file

   Spec_Suffix : constant String := "ads";
   Body_Suffix : constant String := "adb";

   Type_Prefix : constant String := "T ";
   Attr_Prefix : constant String := "A ";

   subtype Base_Type_Node_Kind is Node_Kind range K_Boolean .. K_Long;
   type Base_Type_Node_Array is array (Base_Type_Node_Kind) of Node_Id;
   Base_Types  : Base_Type_Node_Array;
   --  Nodes corresponding for the Pseudo-IDL base types

   type Node_Kind_Image_Array is array (Node_Kind) of Character;
   Image : constant Node_Kind_Image_Array
     := Node_Kind_Image_Array'(K_Boolean               => 'B',
                               K_Octet                 => 'O',
                               K_Long                  => 'L',
                               K_Interface_Declaration => 'I',
                               K_Typedef               => 'T',
                               K_Attribute             => 'A',
                               K_None                  => ' ');

   Module_Name : Name_Id;

   First_Attribute : Node_Id := No_Node;
   Last_Attribute  : Node_Id := No_Node;
   N_Attributes    : Natural := 0;

   First_Interface : Node_Id := No_Node;
   Last_Interface  : Node_Id := No_Node;
   N_Interfaces    : Natural := 0;

   subtype Valid_Node_Id is Node_Id range 1 .. 10_000;
   type Valid_Node_Array is array (Valid_Node_Id) of Node_Type;
   Table : Valid_Node_Array;
   Current_Index : Valid_Node_Id := Valid_Node_Id'First;

   -----------------------------
   -- Copy_Str_At_End_Of_Name --
   -----------------------------

   function Copy_Str_At_End_Of_Name
     (Name  : Name_Id;
      Str   : String)
     return String
   is
      Str_Len : constant Natural := Str'Length;
   begin
      Ocarina.Namet.Get_Name_String (Name);
      for I in Natural range 0 .. Str_Len - 1 loop
         Ocarina.Namet.Name_Buffer (Ocarina.Namet.Name_Len - Str_Len + I + 1)
           := Str (Str'First + I);
      end loop;
      return Ocarina.Namet.Get_Name_String (Ocarina.Namet.Name_Find);
   end Copy_Str_At_End_Of_Name;

   ------------------
   -- First_Entity --
   ------------------

   function First_Entity (N : Node_Id) return Node_Id is
   begin
      return Table (N).First_Entity;
   end First_Entity;

   ----------------
   -- Identifier --
   ----------------

   function Identifier (N : Node_Id) return Name_Id is
   begin
         return Table (N).Identifier;
   end Identifier;

   ----------
   -- Kind --
   ----------

   function Kind (N : Node_Id) return Node_Kind is
   begin
      return Table (N).Kind;
   end Kind;

   -----------------
   -- Last_Entity --
   -----------------

   function Last_Entity (N : Node_Id) return Node_Id is
   begin
      return Table (N).Last_Entity;
   end Last_Entity;

   ---------
   -- Loc --
   ---------

   function Loc (N : Node_Id) return Locations.Location is
   begin
      return Table (N).Loc;
   end Loc;

   --------------
   -- New_Node --
   --------------

   function New_Node
     (Kind : Node_Kind; Loc : Locations.Location)
     return Node_Id
   is
      Node : Node_Id;
   begin
      if Current_Index = Valid_Node_Id'Last then
         return No_Node;
      end if;
      Current_Index := Current_Index + 1;
      Node := Current_Index;

      Table (Node) := Default_Node;
      Table (Node).Kind := Kind;
      Table (Node).Loc  := Loc;

      return Node;
   end New_Node;

   -----------------
   -- Next_Entity --
   -----------------

   function Next_Entity (N : Node_Id) return Node_Id is
   begin
      return Table (N).Next_Entity;
   end Next_Entity;

   ------------------
   -- Scope_Entity --
   ------------------

   function Scope_Entity (N : Node_Id) return Node_Id is
   begin
      return Table (N).Scope_Entity;
   end Scope_Entity;

   ----------------------
   -- Set_First_Entity --
   ----------------------

   procedure Set_First_Entity (N : Node_Id; V : Node_Id) is
   begin
      Table (N).First_Entity := V;
   end Set_First_Entity;

   --------------------
   -- Set_Identifier --
   --------------------

   procedure Set_Identifier (N : Node_Id; V : Name_Id) is
   begin
      Table (N).Identifier := V;
   end Set_Identifier;

   ---------------------
   -- Set_Last_Entity --
   ---------------------

   procedure Set_Last_Entity (N : Node_Id; V : Node_Id) is
   begin
      Table (N).Last_Entity := V;
   end Set_Last_Entity;

   ---------------------
   -- Set_Next_Entity --
   ---------------------

   procedure Set_Next_Entity (N : Node_Id; V : Node_Id) is
   begin
      Table (N).Next_Entity := V;
   end Set_Next_Entity;

   ----------------------
   -- Set_Scope_Entity --
   ----------------------

   procedure Set_Scope_Entity (N : Node_Id; V : Node_Id) is
   begin
      Table (N).Scope_Entity := V;
   end Set_Scope_Entity;

   -------------------
   -- Set_Type_Spec --
   -------------------

   procedure Set_Type_Spec (N : Node_Id; V : Node_Id) is
   begin
      Table (N).Type_Spec := V;
   end Set_Type_Spec;

   ---------------
   -- Type_Spec --
   ---------------

   function Type_Spec (N : Node_Id) return Node_Id is
   begin
      return Table (N).Type_Spec;
   end Type_Spec;

   ---------------
   -- Base_Kind --
   ---------------

   --  As interfaces are represented as Node_Id and as Node_Id is
   --  represented as a long integer, the base type of an interface is
   --  K_Long. For defined types, return the kind of T base type.

   function Base_Kind (T : Node_Id) return Node_Kind is
   begin
      case Kind (T) is
         when K_Interface_Declaration =>
            return K_Long;
         when K_Boolean .. K_Long =>
            return Kind (T);
         when K_Typedef =>
            return Base_Kind (Type_Spec (T));
         when others =>
            return K_None;
      end case;
   end Base_Kind;

   ------------------
   -- Resolve_Type --
   ------------------

   function Resolve_Type (N : Name_Id) return Node_Id is
      Result : Node_Id;
   begin
      Ocarina.Namet.Set_Str_To_Name_Buffer (Type_Prefix);
      Ocarina.Namet.Get_Name_String_And_Append (N);

      Result := Node_Id
        (Ocarina.Namet.Get_Name_Table_Info (Ocarina.Namet.Name_Find));

      if Result = No_Node or else Kind (Result) = K_Attribute then
         return No_Node;
      end if;

      return Result;
   end Resolve_Type;

   ---------
   -- GNS --
   ---------

   function GNS (N : Name_Id) return String is
   begin
      return Ocarina.Namet.Get_Name_String (N);
   end GNS;

   -------------------
   -- Has_Attribute --
   -------------------

   --  Return True when interface I has at least on attribute

   function Has_Attribute (I : Node_Id) return Boolean is
   begin
      return First_Entity (I) /= No_Node;
   end Has_Attribute;

   ----------------------
   -- Mark_As_Adjacent --
   ----------------------

   procedure Mark_As_Adjacent (A : Node_Id; B : Node_Id) is
      X : Node_Id := A;
      Y : Node_Id := B;
   begin
      if B < A then
         X := B;
         Y := A;
      end if;

      Ocarina.Namet.Set_Str_To_Name_Buffer (Attr_Prefix);
      Ocarina.Namet.Get_Name_String_And_Append (Identifier (X));
      Ocarina.Namet.Add_Char_To_Name_Buffer (' ');
      Ocarina.Namet.Get_Name_String_And_Append (Identifier (Y));
      Ocarina.Namet.Set_Name_Table_Byte (Ocarina.Namet.Name_Find, 1);
   end Mark_As_Adjacent;

   -----------
   -- Color --
   -----------

   function Color (N : Node_Id) return Color_Type is
   begin
      return Color_Type (Ocarina.Namet.Get_Name_Table_Info (Identifier (N)));
   end Color;

   -----------------------
   -- Declare_Attribute --
   -----------------------

   procedure Declare_Attribute (A : Node_Id) is
      Type_Name : constant Name_Id := Identifier (Type_Spec (A));
      Attr_Name : constant Name_Id := Identifier (A);
      Attribute : Node_Id;
      N_Errors  : Integer := 0;

   begin
      Attribute := First_Attribute;

      while Attribute /= No_Node loop
         if Identifier (Attribute) = Attr_Name then
            if Identifier (Type_Spec (Attribute)) /= Type_Name then
               Errors.Error_Loc (1) := Loc (A);
               Errors.DE ("attribute type inconsistency");
               N_Errors := N_Errors + 1;
            end if;
         end if;

         exit when N_Errors > 0;

         Attribute := Next_Entity (Attribute);
      end loop;

      if N_Errors = 0 then
         if First_Attribute = No_Node then
            First_Attribute := A;
         end if;

         if Last_Attribute /= No_Node then
            Set_Next_Entity (Last_Attribute, A);
         end if;

         Last_Attribute := A;
         N_Attributes := N_Attributes + 1;
      end if;
   end Declare_Attribute;

   ------------------
   -- Declare_Type --
   ------------------

   procedure Declare_Type (N : Node_Id) is
   begin
      Ocarina.Namet.Set_Str_To_Name_Buffer (Type_Prefix);
      case Kind (N) is
         when K_Boolean =>
            Ocarina.Namet.Add_Str_To_Name_Buffer
              (Lexer.Image (Lexer.T_Boolean));
         when K_Octet =>
            Ocarina.Namet.Add_Str_To_Name_Buffer (Lexer.Image (Lexer.T_Octet));
         when K_Long =>
            Ocarina.Namet.Add_Str_To_Name_Buffer (Lexer.Image (Lexer.T_Long));
         when others =>
            Ocarina.Namet.Get_Name_String_And_Append (Identifier (N));
      end case;

      Ocarina.Namet.Set_Name_Table_Info
        (Ocarina.Namet.Name_Find, Int (N));

      case Kind (N) is
         when K_Boolean =>
            Ocarina.Namet.Set_Str_To_Name_Buffer ("Boolean");
            Set_Identifier (N, Ocarina.Namet.Name_Find);
         when K_Octet =>
            Ocarina.Namet.Set_Str_To_Name_Buffer ("Byte");
            Set_Identifier (N, Ocarina.Namet.Name_Find);
         when K_Long =>
            Ocarina.Namet.Set_Str_To_Name_Buffer ("Int");
            Set_Identifier (N, Ocarina.Namet.Name_Find);
         when others =>
            null;
      end case;
   end Declare_Type;

   ---------------
   -- Generated --
   ---------------

   function Generated (N : Node_Id) return Boolean is
   begin
      return Ocarina.Namet.Get_Name_Table_Byte (Identifier (N)) = 1;
   end Generated;

   ----------------------
   -- Inheritance_Tree --
   ----------------------

   function Inheritance_Tree (I : Node_Id) return Node_Array is
      Parent : Node_Id;
      Tree   : Node_Array;
      Index  : Node_Array_Range := 1;

   begin
      pragma Assert (Kind (I) = K_Interface_Declaration);

      for I in Node_Array_Range loop
         Tree (I) := No_Node;
      end loop;

      Parent := I;
      loop
         Parent := Type_Spec (Parent);
         exit when Parent = No_Node;
         Index := Index + 1;
      end loop;

      Parent := I;
      loop
         Tree (Index) := Parent;
         Parent := Type_Spec (Parent);
         exit when Parent = No_Node;
         Index := Index - 1;
      end loop;

      return Tree;
   end Inheritance_Tree;

   -------------------------------
   -- Is_Attribute_In_Interface --
   -------------------------------

   function Is_Attribute_In_Interface
     (Attribute : Node_Id;
      Intf     : Node_Id)
     return Boolean
   is
      N : constant Name_Id := Identifier (Attribute);
      I : Node_Id := Intf;
   begin
      while I /= No_Node loop
         if Has_Attribute (I) then
            for A in Node_Id
              range First_Entity (I) .. Last_Entity (I)
            loop
               if Identifier (A) = N then
                  return True;
               end if;
            end loop;
         end if;
         I := Type_Spec (I);
      end loop;

      return False;
   end Is_Attribute_In_Interface;

   --------------------------------
   -- Add_Attribute_To_Interface --
   --------------------------------

   procedure Add_Attribute_To_Interface
     (Attribute : Node_Id;
      Intf     : Node_Id) is
   begin
      --  Attribute nodes are contiguous. There is no need to chain them

      if First_Entity (Intf) = No_Node then
         Set_First_Entity (Intf, Attribute);
      end if;
      Set_Last_Entity (Intf, Attribute);
   end Add_Attribute_To_Interface;

   -----------------
   -- P_Attribute --
   -----------------

   function P_Attribute return Node_Id is
      Attribute : Node_Id;
      Type_Spec : Node_Id;
   begin
      --  Parse type specifier

      Lexer.Scan_Token;
      Type_Spec := Resolve_Type (Lexer.Token_Name);

      if Type_Spec = No_Node then
         Errors.Error_Loc (1) := Lexer.Token_Location;
         Errors.DE ("unknown type");
         return No_Node;
      end if;

      Attribute := New_Node (K_Attribute, Lexer.Token_Location);
      Set_Type_Spec (Attribute, Type_Spec);

      --  Parse identifier

      Lexer.Scan_Token (Lexer.T_Identifier);

      if Lexer.Token = Lexer.T_Error then
         return No_Node;
      end if;

      Set_Identifier (Attribute, Lexer.Token_Name);

      Declare_Attribute (Attribute);

      Lexer.Scan_Token (Lexer.T_Semi_Colon);

      if Lexer.Token = Lexer.T_Error then
         return No_Node;
      end if;

      return Attribute;
   end P_Attribute;

   -----------------
   -- P_Interface --
   -----------------

   function P_Interface return Node_Id is
      Intf     : Node_Id;
      Attribute : Node_Id;
      Type_Spec : Node_Id;
   begin
      Lexer.Scan_Token; --  past "interface"
      Intf := New_Node (K_Interface_Declaration, Lexer.Token_Location);

      --  Parse identifier

      Lexer.Scan_Token (Lexer.T_Identifier);

      if Lexer.Token = Lexer.T_Error then
         return No_Node;
      end if;

      Set_Identifier (Intf, Lexer.Token_Name);

      if Resolve_Type (Identifier (Intf)) /= No_Node then
         Errors.Error_Loc (1) := Lexer.Token_Location;
         Errors.DE ("interface already defined");
         return No_Node;
      end if;

      if First_Interface = No_Node then
         First_Interface := Intf;
      end if;

      if Last_Interface /= No_Node then
         Set_Next_Entity (Last_Interface, Intf);
      end if;

      Last_Interface := Intf;
      N_Interfaces := N_Interfaces + 1;

      Lexer.Scan_Token
        (Lexer.Token_List_Type'
           (Lexer.T_Left_Brace,
            Lexer.T_Colon));

      if Lexer.Token = Lexer.T_Error then
         return No_Node;
      end if;

      if Lexer.Token = Lexer.T_Colon then
         --  Parse interface inheritance spec

         Lexer.Scan_Token (Lexer.T_Identifier);

         if Lexer.Token = Lexer.T_Error then
            return No_Node;
         end if;

         Type_Spec := Resolve_Type (Lexer.Token_Name);

         if Type_Spec = No_Node
           or else Kind (Type_Spec) /= K_Interface_Declaration
         then
            Errors.Error_Loc (1) := Lexer.Token_Location;
            Errors.DE ("unknown interface");
            return No_Node;
         end if;

         Set_Type_Spec (Intf, Type_Spec);

         Lexer.Scan_Token (Lexer.T_Left_Brace);

         if Lexer.Token = Lexer.T_Error then
            return No_Node;
         end if;
      end if;

      Declare_Type (Intf);

      loop
         case Lexer.Next_Token is
            when Lexer.T_Identifier
              | Lexer.T_Boolean
              | Lexer.T_Octet
              | Lexer.T_Long =>
               Attribute := P_Attribute;

               if Is_Attribute_In_Interface (Attribute, Intf) then
                  Errors.Error_Loc (1) := Loc (Attribute);
                  Errors.DE ("attribute already defined");
                  return No_Node;
               end if;

               Set_Scope_Entity (Attribute, Intf);
               Add_Attribute_To_Interface (Attribute, Intf);

            when Lexer.T_Right_Brace =>
               Lexer.Scan_Token;
               exit;

            when others =>
               return No_Node;
         end case;
      end loop;

      return Intf;
   end P_Interface;

   ---------------
   -- P_Typedef --
   ---------------

   function P_Typedef return Node_Id is
      Type_Spec : Node_Id;
      Type_Decl : Node_Id;

   begin
      Lexer.Scan_Token; --  past "typedef"
      Type_Decl := New_Node (K_Typedef, Lexer.Token_Location);

      --  Parse type spec

      Lexer.Scan_Token
        (Lexer.Token_List_Type'
           (Lexer.T_Identifier,
            Lexer.T_Boolean,
            Lexer.T_Octet,
            Lexer.T_Long));

      if Lexer.Token = Lexer.T_Error then
         return No_Node;
      end if;

      Type_Spec := Resolve_Type (Lexer.Token_Name);

      if Type_Spec = No_Node then
         Errors.Error_Loc (1) := Lexer.Token_Location;
         Errors.DE ("unknown type");
         return No_Node;
      end if;

      Set_Type_Spec (Type_Decl, Type_Spec);

      --  Parse identifier

      Lexer.Scan_Token (Lexer.T_Identifier);

      if Lexer.Token = Lexer.T_Error then
         return No_Node;
      end if;

      Set_Identifier (Type_Decl, Lexer.Token_Name);

      if Resolve_Type (Identifier (Type_Decl)) /= No_Node then
         Errors.Error_Loc (1) := Lexer.Token_Location;
         Errors.DE ("type already defined");
         return No_Node;
      end if;

      Declare_Type (Type_Decl);

      return Type_Decl;
   end P_Typedef;

   ------------------
   -- P_Definition --
   ------------------

   function P_Definition return Node_Id is
      Definition : Node_Id := No_Node;
      State      : Locations.Location;
   begin
      Lexer.Save_Lexer (State);
      Lexer.Scan_Token
        (Lexer.Token_List_Type'
           (Lexer.T_Typedef,
            Lexer.T_Interface));
      case Lexer.Token is
         when Lexer.T_Typedef =>
            Lexer.Restore_Lexer (State);
            Definition := P_Typedef;

         when Lexer.T_Interface =>
            Lexer.Restore_Lexer (State);
            Definition := P_Interface;

         when others =>
            null;
      end case;

      if Definition /= No_Node then
         Lexer.Save_Lexer (State);
         Lexer.Scan_Token (Lexer.T_Semi_Colon);

         if Lexer.Token /= Lexer.T_Semi_Colon then
            Definition := No_Node;
         end if;
      end if;

      if Definition = No_Node then
         Lexer.Restore_Lexer (State);
         Lexer.Skip_Declaration (Lexer.T_Semi_Colon);
      end if;

      return Definition;
   end P_Definition;

   -----------
   -- Quote --
   -----------

   function Quote (S : String) return String is
   begin
      return """" & S & """";
   end Quote;

   ---------
   -- WS --
   ---------

   function WS (S : String) return String is
   begin
      return "Set_" & S;
   end WS;

   ---------------
   -- Set_Color --
   ---------------

   procedure Set_Color (N : Node_Id; V : Color_Type) is
   begin
      Ocarina.Namet.Set_Name_Table_Info (Identifier (N), Int (V));
   end Set_Color;

   -------------------
   -- Set_Generated --
   -------------------

   procedure Set_Generated (N : Node_Id; B : Boolean) is
   begin
      if B then
         Ocarina.Namet.Set_Name_Table_Byte (Identifier (N), Byte (1));
      else
         Ocarina.Namet.Set_Name_Table_Byte (Identifier (N), Byte (0));
      end if;
   end Set_Generated;

   -----------
   -- Usage --
   -----------

   procedure Usage is
   begin
      Set_Standard_Error;
      Write_Line ("Usage: ");
      Write_Line ("      mknodes [options] filename");
      Write_Eol;
      Write_Line ("  General purpose options:");
      Write_Line ("   -D ARG  Generate files in given directory");
      Write_Line ("   -d      Output debugging info");
      Write_Line ("   -O      Exclude code to dump tree");
      Write_Line ("   -p      Output files on stdout");
      Write_Eol;
   end Usage;

   ------------------
   -- Are_Adjacent --
   ------------------

   function Are_Adjacent (A, B : Node_Id) return Boolean is
      X : Node_Id := A;
      Y : Node_Id := B;
   begin
      if B < A then
         X := B;
         Y := A;
      end if;

      Ocarina.Namet.Set_Str_To_Name_Buffer (Attr_Prefix);
      Ocarina.Namet.Get_Name_String_And_Append (Identifier (X));
      Ocarina.Namet.Add_Char_To_Name_Buffer (' ');
      Ocarina.Namet.Get_Name_String_And_Append (Identifier (Y));

      if Ocarina.Namet.Get_Name_Table_Byte (Ocarina.Namet.Name_Find) = 1 then
         return True;
      end if;
      return False;
   end Are_Adjacent;

   -------------------------------
   -- Assign_Color_To_Attribute --
   -------------------------------

   procedure Assign_Color_To_Attribute (Attribute : Node_Id) is
      Kind  : constant Node_Kind := Base_Kind (Type_Spec (Attribute));
      Used  : Color_Flag_Array;
      Attr  : Node_Id;
      Name  : constant Name_Id := Identifier (Attribute);
      Intf : Node_Id;

   begin
      if Debug then
         Write_Str  ("--  Assign color to ");
         Ocarina.Namet.Write_Name (Identifier (Attribute));
         Write_Eol;
      end if;

      for I in Color_Flag_Range loop
         Used (I) := False;
      end loop;

      Attr := First_Attribute;
      while Attr /= No_Node loop
         if Identifier (Attr) = Name then
            Intf := Scope_Entity (Attr);

            if Debug then
               Write_Str ("--   Found attribute in ");
               Ocarina.Namet.Write_Name (Identifier (Intf));
               Write_Eol;
            end if;

            while Intf /= No_Node loop
               --  Mark adjacent attributes. Attribute A2 is adjacent
               --  to attribute A1 when A2 and A1 belong to a common
               --  interface. To do this we must:

               --  1 - Traverse the list of the parent interfaces and
               --  get all the attributes of these parents.

               --  2 - Traverse the list of all the child interfaces
               --  and get all the attributes of these children.
               --  However this kind of traversal is very complex to
               --  perform because the child interfaces do not form a
               --  list but a tree. We use the following workaround
               --  that has the same effect: each time we find a
               --  couple of adjacent attributes, we mark this couple.

               if Has_Attribute (Intf) then
                  for Adjacent in Node_Id
                    range First_Entity (Intf) .. Last_Entity (Intf)
                  loop
                     --  Mark the two attributes as adjacent

                     Mark_As_Adjacent (Attribute, Adjacent);
                  end loop;
               end if;

               Intf := Type_Spec (Intf);
            end loop;
         end if;

         Attr := Next_Entity (Attr);
      end loop;

      --  Second pass to complete the work. We search all the
      --  attributes that are adjacent with `Attribute' and we set
      --  their color as used. Note that the number of such attributes
      --  is *greater than* or equal the number of attributes marked
      --  in the previous phase. It could be greater because
      --  attributes belonging to child interfaces could be handled
      --  before `Attribute'.

      Attr := First_Attribute;
      while Attr /= No_Node loop
         if Are_Adjacent (Attribute, Attr) then
            if Debug then
               Write_Str ("--     Conflict with ");
               Ocarina.Namet.Write_Name (Identifier (Attr));
               Write_Str (" from ");
               Ocarina.Namet.Write_Name (Identifier (Scope_Entity (Attr)));
               Write_Str (" ");
               Write_Int (Int (Color (Attr)));
               Write_Eol;
            end if;

            Used (Color (Attr)) := True;
         end if;

         Attr := Next_Entity (Attr);
      end loop;

      --  Find a color not used by adjacent attributes

      for C in Color_Flag_Range loop
         if not Used (C) then
            Set_Color (Attribute, C);

            if Color (Base_Types (Kind)) < C then
               Set_Color (Base_Types (Kind), C);
            end if;

            if Debug then
               Write_Str ("--   Decide to assign ");
               Write_Int (C);
               Write_Str (" to ");
               Ocarina.Namet.Write_Name (Identifier (Attribute));
               Write_Eol;
            end if;

            exit;
         end if;
      end loop;
   end Assign_Color_To_Attribute;

   -------
   -- W --
   -------

   function W (S : String) return String is
   begin
      return "W_" & S;
   end W;

   -----------------------
   -- W_Comment_Message --
   -----------------------

   procedure W_Comment_Message is
   begin
      Write_Line ("--  This file has been generated automatically"
                 & " by `mknodes'. Do not");
      Write_Line ("--  hand modify this file since your changes"
                 & " will be overridden.");
      Write_Eol;
   end W_Comment_Message;

   -------------------
   -- W_Indentation --
   -------------------

   procedure W_Indentation (N : Natural) is
   begin
      for I in Natural range 1 .. N loop
         Write_Str ("   ");
      end loop;
   end W_Indentation;

   -----------------------
   -- W_Subprogram_Call --
   -----------------------

   procedure W_Subprogram_Call
     (I   : Natural;
      F   : String;
      PN1 : String)
   is
   begin
      W_Subprogram_Call (I, F, PN1, No_Str, No_Str, No_Str);
   end W_Subprogram_Call;

   procedure W_Subprogram_Call
     (I   : Natural;
      F   : String;
      PN1 : String;
      PN2 : String)
   is
   begin
      W_Subprogram_Call (I, F, PN1, PN2, No_Str, No_Str);
   end W_Subprogram_Call;

   procedure W_Subprogram_Call
     (I   : Natural;
      F   : String;
      PN1 : String;
      PN2 : String;
      PN3 : String)
   is
   begin
      W_Subprogram_Call (I, F, PN1, PN2, PN3, No_Str);
   end W_Subprogram_Call;

   procedure W_Subprogram_Call
     (I   : Natural;
      F   : String;
      PN1 : String;
      PN2 : String;
      PN3 : String;
      PN4 : String) is
   begin
      W_Indentation (I);
      Write_Line (F);

      if PN1 /= No_Str then
         W_Indentation (I);
         Write_Str ("  (");
         Write_Str (PN1);
      end if;

      if PN2 /= No_Str then
         Write_Line (",");
         W_Indentation (I + 1);
         Write_Str (PN2);
      end if;

      if PN3 /= No_Str then
         Write_Line (",");
         W_Indentation (I + 1);
         Write_Str (PN3);
      end if;

      if PN4 /= No_Str then
         Write_Line (",");
         W_Indentation (I + 1);
         Write_Str (PN4);
      end if;

      Write_Line (");");
   end W_Subprogram_Call;

   ----------------------------
   -- W_Subprogram_Signature --
   ----------------------------

   procedure W_Subprogram_Signature
     (I   : Natural;
      F   : String;
      PN1 : Character;
      PT1 : String;
      PN2 : Character;
      PT2 : String) is
   begin
      W_Indentation (I);

      if PN2 = ' ' and then PT2 /= No_Str then
         Write_Str  ("function");
      else
         Write_Str  ("procedure");
      end if;

      Write_Str  (" ");
      Write_Str  (F);
      Write_Str  (" (");
      Write_Char (PN1);
      Write_Str  (" : ");
      Write_Str  (PT1);

      if PT2 = No_Str then
         Write_Char (')');

      elsif PN2 = ' ' then
         Write_Str  (") return ");
         Write_Str  (PT2);

      else
         Write_Str  ("; ");
         Write_Char (PN2);
         Write_Str  (" : ");
         Write_Str  (PT2);
         Write_Char (')');
      end if;
   end W_Subprogram_Signature;

   ------------------------------
   -- W_Subprogram_Declaration --
   ------------------------------

   procedure W_Subprogram_Declaration
     (I   : Natural;
      F   : String;
      PN1 : Character;
      PT1 : String;
      PN2 : Character;
      PT2 : String) is
   begin
      W_Subprogram_Signature (I, F, PN1, PT1, PN2, PT2);
      Write_Line (";");
   end W_Subprogram_Declaration;

   -----------------------------
   -- W_Subprogram_Definition --
   -----------------------------

   procedure W_Subprogram_Definition
     (I   : Natural;
      F   : String;
      PN1 : Character;
      PT1 : String;
      PN2 : Character;
      PT2 : String) is
   begin
      W_Subprogram_Signature (I, F, PN1, PT1, PN2, PT2);
      Write_Line (" is");
      W_Indentation (I);
      Write_Line ("begin");
   end W_Subprogram_Definition;

   ---------------------------------
   -- W_Subprogram_Definition_End --
   ---------------------------------

   procedure W_Subprogram_Definition_End
     (I   : Natural;
      F   : String) is
   begin
      W_Indentation (I);
      Write_Line ("end " & F & ";");
   end W_Subprogram_Definition_End;

   --------------------
   -- W_Table_Access --
   --------------------

   procedure W_Table_Access (N : Character; A : String) is
   begin
      Write_Str  ("Table (Node_Id (");
      Write_Char (N);
      Write_Str  (")).");
      Write_Str  (A);
   end W_Table_Access;

   ---------------------
   -- W_Pragma_Assert --
   ---------------------

   procedure W_Pragma_Assert (Attribute : Node_Id) is
      Intf : Node_Id;

   begin
      W_Indentation (2);
      Write_Str     ("pragma Assert (False");

      Intf := First_Interface;
      while Intf /= No_Node loop
         if Is_Attribute_In_Interface (Attribute, Intf) then
            Write_Eol;
            W_Indentation (2);
            Write_Str  ("  or else ");
            W_Table_Access ('N', "Kind");
            Write_Str  (" = K_");
            Ocarina.Namet.Write_Name (Identifier (Intf));
         end if;

         Intf := Next_Entity (Intf);
      end loop;

      Write_Line (");");
      Write_Eol;
   end W_Pragma_Assert;

   ----------------------
   -- W_Type_Attribute --
   ----------------------

   procedure W_Type_Attribute (A : String; T : String) is
   begin
      W_Indentation (2);
      Write_Str  (A);
      Write_Str  (" : ");
      Write_Str  (T);
      Write_Line (";");
   end W_Type_Attribute;

   ----------------------
   -- W_Type_Attribute --
   ----------------------

   procedure W_Type_Attribute (K : Node_Kind) is
   begin
      W_Indentation (2);
      Write_Char (Image (K));
      Write_Str  (" : ");
      Ocarina.Namet.Write_Name  (Identifier (Base_Types (K)));
      Write_Line ("_Array;");
   end W_Type_Attribute;

   ----------------------
   -- W_Attribute_Body --
   ----------------------

   procedure W_Attribute_Body (A : Node_Id) is
      K  : Node_Kind;
      NS : Node_Id;
   begin
      NS := Scope_Entity (A);
      while Type_Spec (NS) /= No_Node loop
         NS := Type_Spec (NS);
      end loop;
      K := Base_Kind (Type_Spec (A));
      W_Subprogram_Definition
        (1, GNS (Identifier (A)),
         'N', GNS (Identifier (NS)),
         ' ', GNS (Identifier (Type_Spec (A))));
      W_Pragma_Assert (A);
      W_Indentation (2);
      Write_Str  ("return ");
      Ocarina.Namet.Write_Name (Identifier (Type_Spec (A)));
      Write_Str  (" (");
      Ocarina.Namet.Set_Char_To_Name_Buffer (Image (K));
      Ocarina.Namet.Add_Str_To_Name_Buffer  (" (");
      Ocarina.Namet.Add_Nat_To_Name_Buffer  (Int (Color (A)));
      Ocarina.Namet.Add_Char_To_Name_Buffer (')');
      W_Table_Access ('N', GNS (Ocarina.Namet.Name_Find));
      Write_Line (");");
      W_Subprogram_Definition_End (1, GNS (Identifier (A)));
      Write_Eol;

      W_Subprogram_Definition
        (1, WS (GNS (Identifier (A))),
         'N', GNS (Identifier (NS)),
         'V', GNS (Identifier (Type_Spec (A))));
      W_Pragma_Assert (A);
      W_Indentation (2);
      Ocarina.Namet.Set_Char_To_Name_Buffer (Image (K));
      Ocarina.Namet.Add_Str_To_Name_Buffer  (" (");
      Ocarina.Namet.Add_Nat_To_Name_Buffer  (Int (Color (A)));
      Ocarina.Namet.Add_Char_To_Name_Buffer (')');
      W_Table_Access ('N', GNS (Ocarina.Namet.Name_Find));
      Write_Str  (" := ");
      Ocarina.Namet.Write_Name (Identifier (Base_Types (K)));
      Write_Line (" (V);");
      W_Subprogram_Definition_End (1, WS (GNS (Identifier (A))));
      Write_Eol;
   end W_Attribute_Body;

   ----------------------
   -- W_Attribute_Body --
   ----------------------

   procedure W_Attribute_Body (A : String; N : String; T : String) is
   begin
      W_Subprogram_Definition (1, A, 'N', N, ' ', T);
      W_Indentation (2);
      Write_Str  ("return ");
      W_Table_Access ('N', A);
      Write_Line (";");
      W_Subprogram_Definition_End (1, A);
      Write_Eol;

      W_Subprogram_Definition (1, WS (A), 'N', N, 'V', T);
      W_Indentation (2);
      W_Table_Access ('N', A);
      Write_Line (" := V;");
      W_Subprogram_Definition_End (1, WS (A));
      Write_Eol;
   end W_Attribute_Body;

   ----------------------
   -- W_Attribute_Spec --
   ----------------------

   procedure W_Attribute_Spec (A : String; N : String; T : String) is
   begin
      W_Subprogram_Declaration (1, A, 'N', N, ' ', T);
      W_Subprogram_Declaration (1, WS (A), 'N', N, 'V', T);
   end W_Attribute_Spec;

   ----------------------
   -- W_Attribute_Spec --
   ----------------------

   procedure W_Attribute_Spec (A : Node_Id) is
      NS   : Node_Id;
   begin
      NS := Scope_Entity (A);

      while Type_Spec (NS) /= No_Node loop
         NS := Type_Spec (NS);
      end loop;

      W_Attribute_Spec
        (GNS (Identifier (A)),
         GNS (Identifier (NS)),
         GNS (Identifier (Type_Spec (A))));
   end W_Attribute_Spec;

   ------------
   -- W_With --
   ------------

   procedure W_With (P : String) is
   begin
      Write_Line ("with " & P & "; use " & P & ";");
   end W_With;

   --------------------
   -- W_Package_Body --
   --------------------

   procedure W_Package_Body is
      Attribute : Node_Id;
      Intf     : Node_Id;
      Base_Type : Node_Id;
   begin
      Write_Line ("pragma Style_Checks (""NM32766"");");
      Write_Eol;

      W_Comment_Message;

      W_With (Copy_Str_At_End_Of_Name (Module_Name, "Debug"));
      Write_Eol;
      Write_Str ("package body ");
      Ocarina.Namet.Write_Name (Module_Name);
      Write_Line (" is");
      Write_Eol;
      W_Indentation (1);
      Write_Line ("pragma Warnings (Off);");
      W_Indentation (1);
      Write_Line ("use Entries;");
      Write_Eol;

      W_Attribute_Body ("Kind", "Node_Id", "Node_Kind");
      W_Attribute_Body ("Loc", "Node_Id", "Location");

      --  Some attributes may appear several times in different
      --  interfaces. We do not want to generate them several
      --  times. We mark attributes as not generated and when we visit
      --  them we mark them back as generated.

      Attribute := First_Attribute;
      while Attribute /= No_Node loop
         Set_Generated (Attribute, False);
         Attribute := Next_Entity (Attribute);
      end loop;

      --  We generate a getter/setter for each attribute. We mark them
      --  as generated in order not to generate them several
      --  times. See above.

      Attribute := First_Attribute;
      while Attribute /= No_Node loop
         if not Generated (Attribute) then
            W_Attribute_Body (Attribute);
            Set_Generated (Attribute, True);
         end if;

         Attribute := Next_Entity (Attribute);
      end loop;

      W_Subprogram_Definition
        (1, W ("Node"), 'N', "Node_Id", ' ', No_Str);
      W_Indentation (2);

      if not Dump_Tree then
         Write_Line ("null;");

      else
         Write_Line ("case Kind (N) is");
         Intf := First_Interface;

         while Intf /= No_Node loop
            if Type_Spec (Intf) /= No_Node then
               W_Indentation (3);
               Write_Str  ("when K_");
               Ocarina.Namet.Write_Name (Identifier (Intf));
               Write_Line (" =>");
               Base_Type := Intf;

               while Type_Spec (Base_Type) /= No_Node loop
                  Base_Type := Type_Spec (Base_Type);
               end loop;

               W_Subprogram_Call
                 (4, W (GNS (Identifier (Intf))),
                  GNS (Identifier (Base_Type)) & " (N)");
            end if;

            Intf := Next_Entity (Intf);
         end loop;

         W_Indentation (3);
         Write_Line ("when others =>");
         W_Indentation (4);
         Write_Line ("null;");
         W_Indentation (2);
         Write_Line ("end case;");
      end if;

      W_Subprogram_Definition_End (1, W ("Node"));
      Write_Eol;

      if Dump_Tree then
         Intf := First_Interface;

         while Intf /= No_Node loop
            if Type_Spec (Intf) /= No_Node then
               Base_Type := Intf;

               while Type_Spec (Base_Type) /= No_Node loop
                  Base_Type := Type_Spec (Base_Type);
               end loop;

               W_Subprogram_Definition
                 (1, W (GNS (Identifier (Intf))),
                  'N', GNS (Identifier (Base_Type)),
                    ' ', No_Str);

               W_Subprogram_Call
                 (2, W ("Node_Header"), "Node_Id (N)");

               Attribute := First_Attribute;
               while Attribute /= No_Node loop
                  Set_Generated (Attribute, False);
                  Attribute := Next_Entity (Attribute);
               end loop;

               Attribute := First_Attribute;
               while Attribute /= No_Node loop
                  if not Generated (Attribute)
                    and then Is_Attribute_In_Interface (Attribute, Intf)
                  then
                     if Kind (Type_Spec (Attribute)) =
                       K_Interface_Declaration
                     then
                        W_Subprogram_Call
                          (2, W ("Node_Attribute"),
                           Quote (GNS (Identifier (Attribute))),
                           Quote (GNS (Identifier (Type_Spec (Attribute)))),
                           "Image (" & GNS (Identifier (Attribute)) & " (N))",
                           "Int (" & GNS (Identifier (Attribute)) & " (N))");
                     else
                        W_Subprogram_Call
                          (2, W ("Node_Attribute"),
                           Quote (GNS (Identifier (Attribute))),
                           Quote (GNS (Identifier (Type_Spec (Attribute)))),
                           "Image (" & GNS (Identifier (Attribute)) & " (N))");
                     end if;

                     Set_Generated (Attribute, True);
                  end if;

                  Attribute := Next_Entity (Attribute);
               end loop;

               W_Subprogram_Definition_End
                 (1, W (GNS (Identifier (Intf))));
               Write_Eol;
            end if;

            Intf := Next_Entity (Intf);
         end loop;
      end if;

      Write_Str  ("end ");
      Ocarina.Namet.Write_Name (Module_Name);
      Write_Line (";");
   end W_Package_Body;

   --------------------
   -- W_Package_Spec --
   --------------------

   procedure W_Package_Spec is
      Intf : Node_Id;
      Attr : Node_Id;
      Tree : Node_Array;

   begin
      Write_Line ("pragma Style_Checks (""NM32766"");");
      Write_Eol;

      W_Comment_Message;

      Write_Line ("with GNAT.Table;");

      --  The packages Locations and Types may have been included by a
      --  parent package of the generated package (or may not). We
      --  disable a warning generated when enabling the GNAT style
      --  checks.

      Write_Line ("pragma Warnings (Off);");
      Write_Line ("with Locations; use Locations;");
      Write_Line ("with Types;     use Types;");
      Write_Line ("pragma Warnings (On);");
      Write_Eol;
      Write_Str  ("package ");
      Ocarina.Namet.Write_Name (Module_Name);
      Write_Line (" is");
      Write_Eol;

      --  Describe Node_Kind type (all interfaces)

      W_Indentation (1);
      Write_Line  ("type Node_Kind is");
      W_Indentation (1);
      Write_Str ("  (");

      Intf := First_Interface;
      while Intf /= No_Node loop
         Write_Str  ("K_");
         Ocarina.Namet.Write_Name (Identifier (Intf));

         if Intf = Last_Interface then
            Write_Line (");");
         else
            Write_Line (",");
            W_Indentation (2);
         end if;

         Intf := Next_Entity (Intf);
      end loop;

      Write_Eol;

      --  Describe interface attributes

      Intf := First_Interface;
      while Intf /= No_Node loop
         --  Output a description of interface

         W_Indentation (1);
         Write_Line ("--");
         W_Indentation (1);
         Write_Str  ("--  ");
         Ocarina.Namet.Write_Name (Identifier (Intf));
         Write_Eol;
         W_Indentation (1);
         Write_Line ("--");

         Tree := Inheritance_Tree (Intf);
         for I in Node_Array_Range loop
            exit when Tree (I) = No_Node;
            if Has_Attribute (Tree (I)) then
               for A in Node_Id
                 range First_Entity (Tree (I)) .. Last_Entity (Tree (I))
               loop
                  W_Indentation (1);
                  Write_Str  ("--    ");
                  Ocarina.Namet.Get_Name_String (Identifier (A));
                  for J in Natural range 1 .. Ocarina.Namet.Name_Len loop
                     Write_Char (Ocarina.Namet.Name_Buffer (J));
                  end loop;
                  for J in Natural range Ocarina.Namet.Name_Len + 1 .. 25 loop
                     Write_Char (' ');
                  end loop;
                  Write_Str  (": ");
                  Ocarina.Namet.Write_Name  (Identifier (Type_Spec (A)));
                  Write_Eol;
               end loop;
            end if;
         end loop;

         W_Indentation (1);
         Write_Line ("--");
         Write_Eol;

         --  Output signature of interface output when this is not
         --  a basic interface.

         if Dump_Tree then
            if Tree (Tree'First + 1) /= No_Node then
               W_Subprogram_Declaration
                 (1, W (GNS (Identifier (Intf))),
                  'N', GNS (Identifier (Tree (Tree'First))),
                  ' ', No_Str);
               Write_Eol;
            end if;
         end if;

         Intf := Next_Entity (Intf);
      end loop;

      --  Describe attribute accessors

      W_Attribute_Spec ("Kind", "Node_Id", "Node_Kind");
      Write_Eol;
      W_Attribute_Spec ("Loc", "Node_Id", "Location");
      Write_Eol;

      --  Some attributes may appear several times in different
      --  interfaces. We do not want to generate them several
      --  times. We mark attributes as not generated and when we visit
      --  them we mark them back as generated.

      Attr := First_Attribute;
      while Attr /= No_Node loop
         Set_Generated (Attr, False);
         Attr := Next_Entity (Attr);
      end loop;

      --  We generate a getter/setter for each attribute. We mark them
      --  as generated in order not to generate them several
      --  times. See above.

      Attr := First_Attribute;
      while Attr /= No_Node loop
         if not Generated (Attr) then
            W_Attribute_Spec (Attr);
            Write_Eol;
            Set_Generated (Attr, True);
         end if;

         Attr := Next_Entity (Attr);
      end loop;

      W_Subprogram_Declaration
        (1, W ("Node"), 'N', "Node_Id", ' ', No_Str);
      Write_Eol;

      --  Describe slot table types

      for K in Node_Kind range K_Boolean .. K_Long loop
         W_Indentation (1);
         Write_Str  ("type ");
         Ocarina.Namet.Write_Name (Identifier (Base_Types (K)));
         Write_Str  ("_Array is array (1 .. ");
         Write_Int  (Int (Color (Base_Types (K))));
         Write_Str  (") of ");
         Ocarina.Namet.Write_Name (Identifier (Base_Types (K)));
         Write_Line (";");
      end loop;

      Write_Eol;

      --  Describe Node_Entry type and its attributes

      W_Indentation (1);
      Write_Line  ("type Node_Entry is record");
      W_Type_Attribute ("Kind", "Node_Kind");

      for K in Node_Kind range K_Boolean .. K_Long loop
         if Color (Base_Types (K)) > 0 then
            W_Type_Attribute (K);
         end if;
      end loop;

      W_Type_Attribute ("Loc", "Location");
      W_Indentation (1);
      Write_Line  ("end record;");
      Write_Eol;

      --  Provide a default node

      W_Indentation (1);
      Write_Line  ("Default_Node : constant Node_Entry :=");
      W_Indentation (1);
      Write_Line  ("  (Node_Kind'First,");

      for K in Node_Kind range K_Boolean .. K_Long loop
         if Color (Base_Types (K)) > 0 then
            W_Indentation (2);
            Write_Str  ("(others => ");

            if K = K_Boolean then
               Write_Str ("False");
            else
               Write_Int (0);
            end if;

            Write_Line ("),");
         end if;
      end loop;

      W_Indentation (2);
      Write_Line  ("No_Location);");
      Write_Eol;

      --  Provide node table

      W_Indentation (1);
      Write_Line ("package Entries is new GNAT.Table");
      W_Indentation (1);
      Write_Line ("  (Node_Entry, Node_Id, No_Node + 1, 1000, 100);");
      Write_Eol;
      Write_Str  ("end ");
      Ocarina.Namet.Write_Name (Module_Name);
      Write_Line (";");
   end W_Package_Spec;

   ----------
   -- Main --
   ----------

   procedure Main is
      Attribute         : Node_Id;
      Definition        : Node_Id;
      pragma Unreferenced (Definition); --  Because never read

      Dir_Sep_Idx : Natural;

   begin

      --  Initialization step

      Ocarina.Namet.Initialize;
      Errors.Initialize;

      loop
         case GNAT.Command_Line.Getopt ("d O p D:") is
            when 'd' =>
               Debug := True;

            when 'O' =>
               Dump_Tree := False;

            when 'D' =>
               Ocarina.Namet.Set_Str_To_Name_Buffer
                 (GNAT.Command_Line.Parameter);
               Output_Dir := Ocarina.Namet.Name_Find;

               if not GNAT.OS_Lib.Is_Directory
                 (GNAT.Command_Line.Parameter) then
                  Errors.DE (GNAT.Command_Line.Parameter &
                               " is not a valid directory");
                  exit;
               end if;

            when 'p' =>
               Output_File := GNAT.OS_Lib.Standout;

            when ASCII.NUL =>
               exit;

            when others =>
               Errors.DE ("unknown flag");
               exit;
         end case;
      end loop;

      Ocarina.Namet.Set_Str_To_Name_Buffer (GNAT.Command_Line.Get_Argument);
      if Ocarina.Namet.Name_Len = 0 then
         Errors.DE ("no source file provided");
      end if;

      if Errors.N_Errors > 0 then
         Usage;
         GNAT.OS_Lib.OS_Exit (2);
      end if;

      --  Check that source name has ".idl" as prefix. This assumption is
      --  used when we compute spec and body file names.

      Source_Name := Ocarina.Namet.Name_Find;
      if not GNAT.OS_Lib.Is_Regular_File
        (Ocarina.Namet.Get_Name_String (Source_Name))
      then
         Errors.Error_Name (1) := Source_Name;
         Errors.DE ("% not found");
      end if;

      if Ocarina.Namet.Name_Len < 4
        or else Ocarina.Namet.Name_Buffer (Ocarina.Namet.Name_Len - 3) /= '.'
        or else Ocarina.Namet.Name_Buffer (Ocarina.Namet.Name_Len - 2) /= 'i'
        or else Ocarina.Namet.Name_Buffer (Ocarina.Namet.Name_Len - 1) /= 'd'
        or else Ocarina.Namet.Name_Buffer (Ocarina.Namet.Name_Len - 0) /= 'l'
      then
         Errors.DE ("source file name must end with "".idl""");
      end if;

      if Errors.N_Errors > 0 then
         Usage;
         GNAT.OS_Lib.OS_Exit (3);
      end if;

      --  Split dirname from basename in source name. Update Output_Dir
      --  if not already set.

      Dir_Sep_Idx := 0;
      for I in reverse Natural range 1 .. Ocarina.Namet.Name_Len loop
         if Ocarina.Namet.Name_Buffer (I)
           = GNAT.OS_Lib.Directory_Separator
         then
            Dir_Sep_Idx := I;
            exit;
         end if;
      end loop;

      if Output_Dir = No_Name then
         Ocarina.Namet.Name_Len := Dir_Sep_Idx - 1;
         Output_Dir := Ocarina.Namet.Name_Find;
      end if;

      if Debug then
         Write_Str ("output directory is ");
         if Output_Dir /= No_Name then
            Ocarina.Namet.Write_Name (Output_Dir);
         else
            Write_Str ("<no name>");
         end if;
         Write_Eol;
      end if;

      Ocarina.Namet.Get_Name_String (Source_Name);
      for I in Natural range 1 .. Ocarina.Namet.Name_Len - Dir_Sep_Idx loop
         Ocarina.Namet.Name_Buffer (I)
           := Ocarina.Namet.Name_Buffer (Dir_Sep_Idx + I);
      end loop;
      Ocarina.Namet.Name_Len := Ocarina.Namet.Name_Len - Dir_Sep_Idx;
      Output_Name := Ocarina.Namet.Name_Find;

      if Debug then
         Write_Str ("output filename is ");
         if Output_Name /= No_Name then
            Ocarina.Namet.Write_Name (Output_Name);
         else
            Write_Str ("<no name>");
         end if;
         Write_Eol;
      end if;

      --  Open source file

      Ocarina.Namet.Get_Name_String (Source_Name);
      Ocarina.Namet.Name_Buffer (Ocarina.Namet.Name_Len + 1) := ASCII.NUL;
      Source_File := GNAT.OS_Lib.Open_Read
        (Ocarina.Namet.Name_Buffer'Address, GNAT.OS_Lib.Binary);

      --  Lexer step

      Lexer.Process (Source_File, Source_Name);

      for T in Node_Kind range K_Boolean .. K_Long loop
         Base_Types (T) := New_Node (T, Lexer.Token_Location);
         Declare_Type (Base_Types (T));
      end loop;

      Lexer.Scan_Token (Lexer.T_Module);
      if Lexer.Token = Lexer.T_Error then
         Errors.DE ("keyword module expected");
      end if;

      if Errors.N_Errors = 0 then
         Lexer.Scan_Token (Lexer.T_Identifier);
         if Lexer.Token = Lexer.T_Error then
            Errors.DE ("identifier expected");
         end if;
      end if;

      --  Compute Ada package name from IDL module name

      if Errors.N_Errors = 0 then
         Module_Name := Lexer.Token_Name;
         while Lexer.Next_Token = Lexer.T_Colon_Colon loop
            Lexer.Scan_Token;
            Lexer.Scan_Token (Lexer.T_Identifier);
            Ocarina.Namet.Get_Name_String (Module_Name);
            Ocarina.Namet.Add_Char_To_Name_Buffer ('.');
            Ocarina.Namet.Get_Name_String_And_Append (Lexer.Token_Name);
            Module_Name := Ocarina.Namet.Name_Find;
         end loop;

         Lexer.Scan_Token (Lexer.T_Left_Brace);
         if Lexer.Token = Lexer.T_Error then
            Errors.DE ("'{' expected");
         end if;
      end if;

      if Errors.N_Errors = 0 then
         loop
            case Lexer.Next_Token is
               when Lexer.T_Right_Brace =>
                  Lexer.Scan_Token;
                  exit;

               when Lexer.T_EOF =>
                  exit;

               when others =>
                  Definition := P_Definition;
            end case;
         end loop;
         Lexer.Scan_Token (Lexer.T_Semi_Colon);
      end if;

      --  Output a summary on errors and warnings

      if Errors.N_Errors > 0 then
         Errors.Error_Int (1) := Errors.N_Errors;
         Errors.Error_Int (2) := Errors.N_Warnings;

         if Errors.N_Warnings > 0 then
            Errors.DE ("$ error(s) and $ warning(s)");
         else
            Errors.DE ("$ error(s)");
         end if;
         GNAT.OS_Lib.OS_Exit (2);

      elsif Errors.N_Warnings > 0 then
         Errors.Error_Int (1) := Errors.N_Warnings;
         Errors.DE ("$ warning(s)");
      end if;

      --  Allocate slots for each attribute

      Attribute := First_Attribute;
      while Attribute /= No_Node loop
         Set_Color (Attribute, No_Color);
         Attribute := Next_Entity (Attribute);
      end loop;

      for K in Node_Kind range K_Boolean .. K_Long loop
         Set_Color (Base_Types (K), No_Color);

         Attribute := First_Attribute;
         while Attribute /= No_Node loop
            if Base_Kind (Type_Spec (Attribute)) = K
              and then Color (Attribute) = No_Color
            then
               Assign_Color_To_Attribute (Attribute);
            end if;

            Attribute := Next_Entity (Attribute);
         end loop;
      end loop;

      --  If the output is not the standard output, then compute the
      --  output filename. This includes the dirname (Output_Dir) and the
      --  basename (Output_Name).

      if Output_File /= GNAT.OS_Lib.Standout then
         Ocarina.Namet.Name_Len := 0;
         if Output_Dir /= No_Name then
            Ocarina.Namet.Get_Name_String (Output_Dir);
            Ocarina.Namet.Add_Char_To_Name_Buffer
              (GNAT.OS_Lib.Directory_Separator);
         end if;
         Ocarina.Namet.Get_Name_String_And_Append (Output_Name);
         Output_Name := Ocarina.Namet.Name_Find;
      end if;

      --  If the output is not the standard output, compute the spec
      --  filename and redirect output.

      if Output_Name /= No_Name then
         Output_File := GNAT.OS_Lib.Create_File
           (Copy_Str_At_End_Of_Name (Output_Name, Spec_Suffix),
            GNAT.OS_Lib.Binary);
         Set_Output (Output_File);
      end if;

      W_Package_Spec;

      --  If the output is not the standard output, compute the body
      --  filename and redirect output.

      if Output_Name /= No_Name then
         Output_File := GNAT.OS_Lib.Create_File
           (Copy_Str_At_End_Of_Name (Output_Name, Body_Suffix),
            GNAT.OS_Lib.Binary);
         Set_Output (Output_File);
      end if;

      W_Package_Body;
   end Main;

end Parser;

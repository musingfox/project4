%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "header.h"
#include "symtab.h"
#include "semcheck.h"

extern int linenum;
extern FILE	*yyin;
extern char	*yytext;
extern char buf[256];
extern int Opt_Symbol;		/* declared in lex.l */

extern FILE* jfp;
int top = 0;
int condCnt = 0;
int condStack[50];
int labelCnt = -1;
int mainFlag = 0;
int varList[100] = {0};
int varCnt = -1;

int scope = 0;

int readFlag = 0;
char fileName[256];
struct SymTable *symbolTable;
__BOOLEAN paramError;
struct PType *funcReturn;
__BOOLEAN semError = __FALSE;
int inloop = 0;

%}

%union {
	int intVal;
	float floatVal;	
	char *lexeme;
	struct idNode_sem *id;
	struct ConstAttr *constVal;
	struct PType *ptype;
	struct param_sem *par;
	struct expr_sem *exprs;
	struct expr_sem_node *exprNode;
	struct constParam *constNode;
	struct varDeclParam* varDeclNode;
};

%token	LE_OP NE_OP GE_OP EQ_OP AND_OP OR_OP
%token	READ BOOLEAN WHILE DO IF ELSE TRUE FALSE FOR INT PRINT BOOL VOID FLOAT DOUBLE STRING CONTINUE BREAK RETURN CONST
%token	L_PAREN R_PAREN COMMA SEMICOLON ML_BRACE MR_BRACE L_BRACE R_BRACE ADD_OP SUB_OP MUL_OP DIV_OP MOD_OP ASSIGN_OP LT_OP GT_OP NOT_OP

%token <lexeme>ID
%token <intVal>INT_CONST 
%token <floatVal>FLOAT_CONST
%token <floatVal>SCIENTIFIC
%token <lexeme>STR_CONST

%type<ptype> scalar_type dim
%type<par> array_decl parameter_list
%type<constVal> literal_const
%type<constNode> const_list 
%type<exprs> variable_reference logical_expression logical_term logical_factor relation_expression arithmetic_expression term factor logical_expression_list literal_list initial_array
%type<intVal> relation_operator add_op mul_op dimension
%type<varDeclNode> identifier_list


%start program
%%

program :		decl_list 
			    funct_def
				decl_and_def_list 
				{
					if(Opt_Symbol == 1)
					printSymTable( symbolTable, scope );	
				}
		;

decl_list : decl_list var_decl
		  | decl_list const_decl
		  | decl_list funct_decl
		  |
		  ;


decl_and_def_list : decl_and_def_list var_decl
				  | decl_and_def_list const_decl
				  | decl_and_def_list funct_decl
				  | decl_and_def_list funct_def
				  | 
				  ;

		  
funct_def : scalar_type ID L_PAREN R_PAREN 
			{
				funcReturn = $1; 
				struct SymNode *node;
				node = findFuncDeclaration( symbolTable, $2 );
				
				if( node != 0 ){
					verifyFuncDeclaration( symbolTable, 0, $1, node );
				}
				else{
					insertFuncIntoSymTable( symbolTable, $2, 0, $1, scope, __TRUE );
				}
				if (strcmp($2, "main") == 0){
					fprintf(jfp, ".method public static main([Ljava/lang/String;)V\n");
					fprintf(jfp, ".limit stack 100\n");
					fprintf(jfp, ".limit locals 100\n");
					mainFlag = 1;
				}
				else{
					switch ($1->type){
						case INTEGER_t:
							fprintf(jfp, ".method public static %s()I\n", $2);
							break;
						case BOOLEAN_t:
							fprintf(jfp, ".method public static %s()Z\n", $2);
							break;
						case FLOAT_t:
							fprintf(jfp, ".method public static %s()F\n", $2);
							break;
						case DOUBLE_t:
							fprintf(jfp, ".method public static %s()D\n", $2);
							break;
						default:
						break;
					}
					fprintf(jfp, ".limit stack 100\n");
					fprintf(jfp, ".limit locals 100\n");
					mainFlag = 0;
				}
			}
			compound_statement
			{ 
				funcReturn = 0;
				if (strcmp($2, "main") != 0){
					mainFlag = 0;
					switch($1->type){
						case BOOLEAN_t:
						case INTEGER_t:
							fprintf(jfp, "ireturn\n");
							break;
						case FLOAT_t:
							fprintf(jfp, "freturn\n");
							break;
						case DOUBLE_t:
							fprintf(jfp, "dreturn\n");
							break;
						default:
							fprintf(jfp, "return\n");
							break;
					}
				}
				else {
					fprintf(jfp, "return\n");
				}
				fprintf(jfp, ".end method\n");
			}	
		  | scalar_type ID L_PAREN parameter_list R_PAREN  
			{				
				funcReturn = $1;
				
				paramError = checkFuncParam( $4 );
				if( paramError == __TRUE ){
					fprintf( stdout, "########## Error at Line#%d: param(s) with several fault!! ##########\n", linenum );
					semError = __TRUE;
				}
				// check and insert function into symbol table
				else{
					struct SymNode *node;
					node = findFuncDeclaration( symbolTable, $2 );

					if( node != 0 ){
						if(verifyFuncDeclaration( symbolTable, $4, $1, node ) == __TRUE){	
							insertParamIntoSymTable( symbolTable, $4, scope+1, 0 );
						}				
					}
					else{
						insertParamIntoSymTable( symbolTable, $4, scope+1, 0 );				
						insertFuncIntoSymTable( symbolTable, $2, $4, $1, scope, __TRUE );
					}
					struct param_sem* param = $4;
					char paramType[10];
					int cnt=0;
					while (param!=0){
						char temp[1];
						switch (param->pType->type){
							case INTEGER_t:
								paramType[cnt++] = 'I';
								break;
							case BOOLEAN_t:
								paramType[cnt++] = 'Z';
								break;
							case FLOAT_t:
								paramType[cnt++] = 'F';
								break;
							case DOUBLE_t:
								paramType[cnt++] = 'D';
								break;
							default:
							break;
						}
						param = param->next;
					}
					top += cnt;
					paramType[cnt] = '\0';
					switch ($1->type){
						case INTEGER_t:
							fprintf(jfp, ".method public static %s(%s)I\n", $2, paramType);
							break;
						case BOOLEAN_t:
							fprintf(jfp, ".method public static %s(%s)Z\n", $2, paramType);
							break;
						case FLOAT_t:
							fprintf(jfp, ".method public static %s(%s)F\n", $2, paramType);
							break;
						case DOUBLE_t:
							fprintf(jfp, ".method public static %s(%s)D\n", $2, paramType);
							break;
						default:
						break;
					}
					fprintf(jfp, ".limit stack 100\n");
					fprintf(jfp, ".limit locals 100\n");
				}
			} 	
			compound_statement 
			{ 
				funcReturn = 0; 
				if (strcmp($2, "main") != 0){
					mainFlag = 0;
					switch($1->type){
						case BOOLEAN_t:
						case INTEGER_t:
							fprintf(jfp, "ireturn\n");
							break;
						case FLOAT_t:
							fprintf(jfp, "freturn\n");
							break;
						case DOUBLE_t:
							fprintf(jfp, "dreturn\n");
							break;
						default:
							fprintf(jfp, "return\n");
							break;
					}
				}
				else {
					fprintf(jfp, "return\n");
				}
				fprintf(jfp, ".end method\n");
			}
		  | VOID ID L_PAREN R_PAREN 
			{
				funcReturn = createPType(VOID_t); 
				struct SymNode *node;
				node = findFuncDeclaration( symbolTable, $2 );

				if( node != 0 ){
					verifyFuncDeclaration( symbolTable, 0, createPType( VOID_t ), node );					
				}
				else{
					insertFuncIntoSymTable( symbolTable, $2, 0, createPType( VOID_t ), scope, __TRUE );	
				}
				if (strcmp($2, "main") == 0){
					fprintf(jfp, ".method public static main([Ljava/lang/String;)V\n");
					fprintf(jfp, ".limit stack 100\n");
					fprintf(jfp, ".limit locals 100\n");
					mainFlag = 1;
				}
				else{
					fprintf(jfp, ".limit stack 100\n");
					fprintf(jfp, ".limit locals 100\n");
					mainFlag = 0;
				}
			}
			compound_statement { funcReturn = 0; fprintf(jfp, "return\n"); fprintf(jfp, ".end method\n");}	
		  | VOID ID L_PAREN parameter_list R_PAREN
			{									
				funcReturn = createPType(VOID_t);
				
				paramError = checkFuncParam( $4 );
				if( paramError == __TRUE ){
					fprintf( stdout, "########## Error at Line#%d: param(s) with several fault!! ##########\n", linenum );
					semError = __TRUE;
				}
				// check and insert function into symbol table
				else{
					struct SymNode *node;
					node = findFuncDeclaration( symbolTable, $2 );

					if( node != 0 ){
						if(verifyFuncDeclaration( symbolTable, $4, createPType( VOID_t ), node ) == __TRUE){	
							insertParamIntoSymTable( symbolTable, $4, scope+1, 0 );				
						}
					}
					else{
						insertParamIntoSymTable( symbolTable, $4, scope+1, 0 );				
						insertFuncIntoSymTable( symbolTable, $2, $4, createPType( VOID_t ), scope, __TRUE );
					}
					// done function definition
					struct param_sem* param = $4;
					char paramType[10];
					int cnt=0;
					while (param!=0){
						char temp[1];
						switch (param->pType->type){
							case INTEGER_t:
								paramType[cnt++] = 'I';
								break;
							case BOOLEAN_t:
								paramType[cnt++] = 'Z';
								break;
							case FLOAT_t:
								paramType[cnt++] = 'F';
								break;
							case DOUBLE_t:
								paramType[cnt++] = 'D';
								break;
							default:
								paramType[cnt++] = '\0';
								break;
						}
						param = param->next;
					}
					paramType[cnt] = '\0';
					top += cnt;
					fprintf(jfp, ".method public static %s(%s)V\n", $2, paramType);
					fprintf(jfp, ".limit stack 100\n");
					fprintf(jfp, ".limit locals 100\n");
				}
			} 
			compound_statement { funcReturn = 0; fprintf(jfp, "return\n"); fprintf(jfp, ".end method\n");}		  
		  ;

funct_decl : scalar_type ID L_PAREN R_PAREN SEMICOLON
			{
				insertFuncIntoSymTable( symbolTable, $2, 0, $1, scope, __FALSE );	
			}
		   | scalar_type ID L_PAREN parameter_list R_PAREN SEMICOLON
		    {
				paramError = checkFuncParam( $4 );
				if( paramError == __TRUE ){
					fprintf( stdout, "########## Error at Line#%d: param(s) with several fault!! ##########\n", linenum );
					semError = __TRUE;
				}
				else {
					insertFuncIntoSymTable( symbolTable, $2, $4, $1, scope, __FALSE );
				}
			}
		   | VOID ID L_PAREN R_PAREN SEMICOLON
			{				
				insertFuncIntoSymTable( symbolTable, $2, 0, createPType( VOID_t ), scope, __FALSE );
			}
		   | VOID ID L_PAREN parameter_list R_PAREN SEMICOLON
			{
				paramError = checkFuncParam( $4 );
				if( paramError == __TRUE ){
					fprintf( stdout, "########## Error at Line#%d: param(s) with several fault!! ##########\n", linenum );
					semError = __TRUE;	
				}
				else {
					insertFuncIntoSymTable( symbolTable, $2, $4, createPType( VOID_t ), scope, __FALSE );
				}
			}
		   ;

parameter_list : parameter_list COMMA scalar_type ID
			   {
				struct param_sem *ptr;
				ptr = createParam( createIdList( $4 ), $3 );
				param_sem_addParam( $1, ptr );
				$$ = $1;
			   }
			   | parameter_list COMMA scalar_type array_decl
			   {
				$4->pType->type= $3->type;
				param_sem_addParam( $1, $4 );
				$$ = $1;
			   }
			   | scalar_type array_decl 
			   { 
				$2->pType->type = $1->type;  
				$$ = $2;
			   }
			   | scalar_type ID { $$ = createParam( createIdList( $2 ), $1 ); }
			   ;

var_decl : scalar_type identifier_list SEMICOLON
			{
				memset(varList, 0, sizeof(varList));
				struct varDeclParam *ptr;
				struct SymNode *newNode;
				for( ptr=$2 ; ptr!=0 ; ptr=(ptr->next) ) {						
					if( verifyRedeclaration( symbolTable, ptr->para->idlist->value, scope ) == __FALSE ) { }
					else {
						if( verifyVarInitValue( $1, ptr, symbolTable, scope ) ==  __TRUE ){	
							//	done global variables
							if (scope == 0){
								switch (ptr->para->pType->type){
									case INTEGER_t:
										fprintf(jfp, ".field public static %s I\n", ptr->para->idlist->value);
										break;
									case FLOAT_t:
										fprintf(jfp, ".field public static %s F\n", ptr->para->idlist->value);
										break;
									case BOOLEAN_t:
										fprintf(jfp, ".field public static %s Z\n", ptr->para->idlist->value);
										break;
									case DOUBLE_t:
										fprintf(jfp, ".field public static %s D\n", ptr->para->idlist->value);
										break;
									default:
										break;
								}
								newNode = createVarNode( ptr->para->idlist->value, scope, ptr->para->pType, -1 );
								insertTab( symbolTable, newNode );
							}
							else{
								newNode = createVarNode( ptr->para->idlist->value, scope, ptr->para->pType, top++ );
								insertTab( symbolTable, newNode );

								if (ptr->isInit){
									struct SymNode *var = lookupSymbol(symbolTable, ptr->para->idlist->value, scope, __FALSE);
									varList[++varCnt] = var->stackEntry;
								}	
							}		
						}
					}
				}
				if (scope != 0){
					char temp;
					switch ($1->type){
						case INTEGER_t:
							temp = 'I';
							break;
						case FLOAT_t:
							temp = 'F';
							break;
						case BOOLEAN_t:
							temp = 'Z';
							break;
						case DOUBLE_t:
							temp = 'D';
							break;
						default:
							break;
					}
					int i = 0;
					for (i= varCnt ; i >= 0 ; --i){
						if (temp == 'I' || temp == 'Z'){
							fprintf(jfp, "istore %d\n", varList[i]);
						}
						else if (temp == 'D'){
							fprintf(jfp, "dstore %d\n", varList[i]);	
						}
						else
							fprintf(jfp, "fstore %d\n", varList[i]);
					}
				}
			}
			;

identifier_list : identifier_list COMMA ID
				{					
					struct param_sem *ptr;	
					struct varDeclParam *vptr;				
					ptr = createParam( createIdList( $3 ), createPType( VOID_t ) );
					vptr = createVarDeclParam( ptr, 0 );	
					addVarDeclParam( $1, vptr );
					$$ = $1; 					
				}
                | identifier_list COMMA ID ASSIGN_OP logical_expression
				{
					struct param_sem *ptr;	
					struct varDeclParam *vptr;				
					ptr = createParam( createIdList( $3 ), createPType( VOID_t ) );
					vptr = createVarDeclParam( ptr, $5 );
					vptr->isArray = __TRUE;
					vptr->isInit = __TRUE;	
					addVarDeclParam( $1, vptr );	
					$$ = $1;
					
				}
                | identifier_list COMMA array_decl ASSIGN_OP initial_array
				{
					struct varDeclParam *ptr;
					ptr = createVarDeclParam( $3, $5 );
					ptr->isArray = __TRUE;
					ptr->isInit = __TRUE;
					addVarDeclParam( $1, ptr );
					$$ = $1;	
				}
                | identifier_list COMMA array_decl
				{
					struct varDeclParam *ptr;
					ptr = createVarDeclParam( $3, 0 );
					ptr->isArray = __TRUE;
					addVarDeclParam( $1, ptr );
					$$ = $1;
				}
                | array_decl ASSIGN_OP initial_array
				{	
					$$ = createVarDeclParam( $1 , $3 );
					$$->isArray = __TRUE;
					$$->isInit = __TRUE;	
				}
                | array_decl 
				{ 
					$$ = createVarDeclParam( $1 , 0 ); 
					$$->isArray = __TRUE;
				}
                | ID ASSIGN_OP logical_expression
				{
					struct param_sem *ptr;					
					ptr = createParam( createIdList( $1 ), createPType( VOID_t ) );
					$$ = createVarDeclParam( ptr, $3 );		
					$$->isInit = __TRUE;
				}
                | ID 
				{
					struct param_sem *ptr;					
					ptr = createParam( createIdList( $1 ), createPType( VOID_t ) );
					$$ = createVarDeclParam( ptr, 0 );				
				}
                ;
		 
initial_array : L_BRACE literal_list R_BRACE { $$ = $2; }
			  ;

literal_list : literal_list COMMA logical_expression
				{
					struct expr_sem *ptr;
					for( ptr=$1; (ptr->next)!=0; ptr=(ptr->next) );				
					ptr->next = $3;
					$$ = $1;
				}
             | logical_expression
				{
					$$ = $1;
				}
             |
             ;

const_decl 	: CONST scalar_type const_list SEMICOLON
			{
				struct SymNode *newNode;				
				struct constParam *ptr;
				for( ptr=$3; ptr!=0; ptr=(ptr->next) ){
					if( verifyRedeclaration( symbolTable, ptr->name, scope ) == __TRUE ){//no redeclare
						if( ptr->value->category != $2->type ){//type different
							if( !(($2->type==FLOAT_t || $2->type == DOUBLE_t ) && ptr->value->category==INTEGER_t) ) {
								if(!($2->type==DOUBLE_t && ptr->value->category==FLOAT_t)){	
									fprintf( stdout, "########## Error at Line#%d: const type different!! ##########\n", linenum );
									semError = __TRUE;	
								}
								else{
									newNode = createConstNode( ptr->name, scope, $2, ptr->value );
									insertTab( symbolTable, newNode );
								}
							}
							else{
								newNode = createConstNode( ptr->name, scope, $2, ptr->value );
								insertTab( symbolTable, newNode );
							}
						}
						else{
							newNode = createConstNode( ptr->name, scope, $2, ptr->value );
							insertTab( symbolTable, newNode );
						}
					}
				}
			}
			;

const_list : const_list COMMA ID ASSIGN_OP literal_const
			{				
				addConstParam( $1, createConstParam( $5, $3 ) );
				$$ = $1;
			}
		   | ID ASSIGN_OP literal_const
			{
				$$ = createConstParam( $3, $1 );	
			}
		   ;

array_decl : ID dim 
			{
				$$ = createParam( createIdList( $1 ), $2 );
			}
		   ;

dim : dim ML_BRACE INT_CONST MR_BRACE
		{
			if( $3 == 0 ){
				fprintf( stdout, "########## Error at Line#%d: array size error!! ##########\n", linenum );
				semError = __TRUE;
			}
			else
				increaseArrayDim( $1, 0, $3 );			
		}
	| ML_BRACE INT_CONST MR_BRACE	
		{
			if( $2 == 0 ){
				fprintf( stdout, "########## Error at Line#%d: array size error!! ##########\n", linenum );
				semError = __TRUE;
			}			
			else{		
				$$ = createPType( VOID_t ); 			
				increaseArrayDim( $$, 0, $2 );
			}		
		}
	;
	
compound_statement : {scope++;}L_BRACE var_const_stmt_list R_BRACE
					{ 
						// print contents of current scope
						if( Opt_Symbol == 1 )
							printSymTable( symbolTable, scope );
							
						int pop = deleteScope( symbolTable, scope );	// leave this scope, delete...
						scope--; 
					}
				   ;

var_const_stmt_list : var_const_stmt_list statement	
				    | var_const_stmt_list var_decl
					| var_const_stmt_list const_decl
				    |
				    ;

statement : compound_statement
		  | simple_statement
		  | conditional_statement
		  | while_statement
		  | for_statement
		  | function_invoke_statement
		  | jump_statement
		  ;		

simple_statement : variable_reference ASSIGN_OP logical_expression SEMICOLON
					{
						// check if LHS exists
						__BOOLEAN flagLHS = verifyExistence( symbolTable, $1, scope, __TRUE );
						// id RHS is not dereferenced, check and deference
						__BOOLEAN flagRHS = __TRUE;
						if( $3->isDeref == __FALSE ) {
							flagRHS = verifyExistence( symbolTable, $3, scope, __FALSE );
						}
						struct SymNode *curr = lookupSymbol(symbolTable, $1->varRef->id, scope, __FALSE);
						// if both LHS and RHS are exists, verify their type
						if( flagLHS==__TRUE && flagRHS==__TRUE )
							verifyAssignmentTypeMatch( $1, $3 );
						if (curr->scope == 0){
							switch ($1->pType->type){
								case BOOLEAN_t:
									fprintf(jfp, "putstatic output/%s Z\n", curr->name);
									break;
								case INTEGER_t:
									fprintf(jfp, "putstatic output/%s I\n", curr->name);
									break;
								case DOUBLE_t:
									fprintf(jfp, "putstatic output/%s D\n", curr->name);
									break;
								case FLOAT_t:
									fprintf(jfp, "putstatic output/%s F\n", curr->name);
									break;
								default:
									break;
							}
						}
						else {
							switch ($1->pType->type){
								case BOOLEAN_t:
								case INTEGER_t:
									fprintf(jfp, "istore");
									break;
								case DOUBLE_t:
									fprintf(jfp, "dstore");
									break;
								case FLOAT_t:
									fprintf(jfp, "fstore");
									break;
								default:
									break;
							}
							fprintf(jfp, " %d\n", curr->stackEntry);
						}
					}
				 | PRINT {fprintf(jfp, "getstatic java/lang/System/out Ljava/io/PrintStream;\n");} logical_expression SEMICOLON 
				 	{
				 		verifyScalarExpr( $3, "print" );
				 		switch ($3->pType->type){
				 			case BOOLEAN_t:
				 				fprintf(jfp, "invokevirtual java/io/PrintStream/print(Z)V\n");
				 				break;
				 			case INTEGER_t:
					 			fprintf(jfp, "invokevirtual java/io/PrintStream/print(I)V\n");
				 				break;
				 			case FLOAT_t:
					 			fprintf(jfp, "invokevirtual java/io/PrintStream/print(F)V\n");
				 				break;
				 			case DOUBLE_t:
					 			fprintf(jfp, "invokevirtual java/io/PrintStream/print(D)V\n");
				 				break;
				 			case STRING_t:
					 			fprintf(jfp, "invokevirtual java/io/PrintStream/print(Ljava/lang/String;)V\n");
				 				break;
				 			default:
				 				break;
				 		}
				 	}
				 | READ variable_reference SEMICOLON 
					{ 
						if( verifyExistence( symbolTable, $2, scope, __TRUE ) == __TRUE )						
							verifyScalarExpr( $2, "read" );
						if (readFlag == 0){
							fprintf(jfp, "new java/util/Scanner\n");
							fprintf(jfp, "dup\n");
							fprintf(jfp, "getstatic java/lang/System/in Ljava/io/InputStream;\n");
							fprintf(jfp, "invokespecial java/util/Scanner/<init>(Ljava/io/InputStream;)V\n");
							fprintf(jfp, "putstatic output/_sc Ljava/util/Scanner;\n");
							readFlag = 1;
						}
						fprintf(jfp, "getstatic output/_sc Ljava/util/Scanner;\n");
						fprintf(jfp, "invokevirtual java/util/Scanner/");
						//todo : variable reference
						struct SymNode *curr = lookupSymbol(symbolTable, $2->varRef->id, scope, __FALSE);
						if (curr->scope == 0){
							fprintf(jfp, "putstatic output/%s\n", curr->name);
							switch($2->pType->type){
								case INTEGER_t:;
									fprintf(jfp, "I");
									break;
								case BOOLEAN_t:
									fprintf(jfp, "Z");
									break;
								case DOUBLE_t:
									fprintf(jfp, "D");
									break;
								case FLOAT_t:
									fprintf(jfp, "F");
									break;
								default:
									break;
							}
						}
						else {
							switch($2->pType->type){
								case INTEGER_t:
									fprintf(jfp, "nextInt()I\n");
									fprintf(jfp, "istore %d\n", curr->stackEntry);
									break;
								case BOOLEAN_t:
									fprintf(jfp, "nextBoolean()Z\n");
									fprintf(jfp, "istore %d\n", curr->stackEntry);
									break;
								case DOUBLE_t:
									fprintf(jfp, "nextDouble()D\n");
									fprintf(jfp, "dstore %d\n", curr->stackEntry);
									break;
								case FLOAT_t:
									fprintf(jfp, "nextFloat()F\n");
									fprintf(jfp, "fstore %d\n", curr->stackEntry);
									break;
								default:
									break;
							}
						}
					}
				 ;

conditional_statement : IF L_PAREN cond_add conditional_if  R_PAREN compound_statement
						{fprintf(jfp, "Lelse_%d:\n", condStack[condCnt--]);}
					  | IF L_PAREN cond_add conditional_if  R_PAREN compound_statement
					  	{
					  		fprintf(jfp, "goto LExit_%d\n", condStack[condCnt]);
							fprintf(jfp, "Lelse_%d:\n", condStack[condCnt]);
					  	}
						ELSE compound_statement
						{fprintf(jfp, "LExit_%d:\n", condStack[condCnt--]);}
					  ;

cond_add	:	{
					condCnt++;
					labelCnt++;
					condStack[condCnt] = labelCnt;
				}
			;

conditional_if : logical_expression 
					{ 
						verifyBooleanExpr( $1, "if" ); 
						fprintf(jfp, "ifeq Lelse_%d\n", condStack[condCnt]);
					};					  

				
while_statement : WHILE
					{
						condCnt++;
						labelCnt++;
						condStack[condCnt] = labelCnt;
						condStack[condCnt] = labelCnt;
						fprintf(jfp, "LWbegin_%d:\n", condStack[condCnt]);
					}
				  L_PAREN logical_expression 
				  	{ 
				  		verifyBooleanExpr( $4, "while" );
				  		fprintf(jfp, "ifeq LWExit_%d\n", condStack[condCnt]);
				  	} 
				  	R_PAREN { inloop++; }
					compound_statement 
					{ 
						inloop--; 
						fprintf(jfp, "goto LWbegin_%d\n", condStack[condCnt]);
						fprintf(jfp, "LWExit_%d:\n", condStack[condCnt--]);
					}
				| { inloop++; } DO 
					compound_statement WHILE L_PAREN logical_expression R_PAREN SEMICOLON  
					{ 
						 verifyBooleanExpr( $6, "while" );
						 inloop--;
					}
				;


				
for_statement : FOR L_PAREN initial_expression SEMICOLON 
				{
					condCnt++;
					labelCnt++;
					condStack[condCnt] = labelCnt;
					fprintf(jfp, "Lfor_%d:\n", condStack[condCnt]);
				}
				control_expression SEMICOLON 
				{
					fprintf(jfp, "ifeq LforExit_%d\n", condStack[condCnt]);
					fprintf(jfp, "goto LforBlock_%d\n", condStack[condCnt]);
					fprintf(jfp, "LforIncre_%d:\n", condStack[condCnt]);
				}
				increment_expression R_PAREN  
				{ 
					fprintf(jfp, "goto Lfor_%d\n", condStack[condCnt]);
					fprintf(jfp, "LforBlock_%d:\n", condStack[condCnt]);
					inloop++; 
				}
				compound_statement  
				{ 
					fprintf(jfp, "goto LforIncre_%d\n", condStack[condCnt]);
					fprintf(jfp, "LforExit_%d:\n", condStack[condCnt--]);
					inloop--; 
				}
			  ;

initial_expression : initial_expression COMMA statement_for		
				   | initial_expression COMMA logical_expression
				   | logical_expression	
				   | statement_for
				   |
				   ;

control_expression : control_expression COMMA statement_for
				   {
						fprintf( stdout, "########## Error at Line#%d: control_expression is not boolean type ##########\n", linenum );
						semError = __TRUE;	
				   }
				   | control_expression COMMA logical_expression
				   {
						if( $3->pType->type != BOOLEAN_t ){
							fprintf( stdout, "########## Error at Line#%d: control_expression is not boolean type ##########\n", linenum );
							semError = __TRUE;	
						}
				   }
				   | logical_expression 
					{ 
						if( $1->pType->type != BOOLEAN_t ){
							fprintf( stdout, "########## Error at Line#%d: control_expression is not boolean type ##########\n", linenum );
							semError = __TRUE;	
						}
					}
				   | statement_for
				   {
						fprintf( stdout, "########## Error at Line#%d: control_expression is not boolean type ##########\n", linenum );
						semError = __TRUE;	
				   }
				   |
				   ;

increment_expression : increment_expression COMMA statement_for
					 | increment_expression COMMA logical_expression
					 | logical_expression
					 | statement_for
					 |
					 ;

statement_for 	: variable_reference ASSIGN_OP logical_expression
					{
						// check if LHS exists
						__BOOLEAN flagLHS = verifyExistence( symbolTable, $1, scope, __TRUE );
						// id RHS is not dereferenced, check and deference
						__BOOLEAN flagRHS = __TRUE;
						if( $3->isDeref == __FALSE ) {
							flagRHS = verifyExistence( symbolTable, $3, scope, __FALSE );
						}
						// if both LHS and RHS are exists, verify their type
						if( flagLHS==__TRUE && flagRHS==__TRUE )
							verifyAssignmentTypeMatch( $1, $3 );
						switch ($1->pType->type){
							case BOOLEAN_t:
							case INTEGER_t:
								fprintf(jfp, "istore");
								break;
							case DOUBLE_t:
								fprintf(jfp, "dstore");
								break;
							case FLOAT_t:
								fprintf(jfp, "fstore");
								break;
							default:
								break;
						}
						struct SymNode *curr = lookupSymbol(symbolTable, $1->varRef->id, scope, __FALSE);
						fprintf(jfp, " %d\n", curr->stackEntry);
					}
					;
					 
					 
function_invoke_statement : ID L_PAREN logical_expression_list R_PAREN SEMICOLON
							{
								verifyFuncInvoke( $1, $3, symbolTable, scope );
								struct expr_sem *curr = $3;
								char paramType[10];
								int cnt = 0;
								while (curr != 0){
									char type;
									paramType[cnt] = '\0';
									switch (curr->pType->type){
										case INTEGER_t:
											paramType[cnt++] = 'I';
											break;
										case BOOLEAN_t:
											paramType[cnt++] = 'Z';
											break;
										case FLOAT_t:
											paramType[cnt++] = 'F';
											break;
										case DOUBLE_t:
											paramType[cnt++] = 'D';
											break;
										default:
											paramType[cnt++] = '\0';
											break;
									}
									curr = curr->next ;
								}
								paramType[cnt] = '\0';
								fprintf(jfp, "invokestatic output/%s(%s)", $1, paramType);
								struct SymNode *func = lookupSymbol(symbolTable, $1, 0, __FALSE);
								struct PType *pType = func->type;
								switch(pType->type){
									case INTEGER_t:
										fprintf(jfp, "I\n");
										break;
									case BOOLEAN_t:
										fprintf(jfp, "Z\n");
										break;
									case FLOAT_t:
										fprintf(jfp, "F\n");
										break;
									case DOUBLE_t:
										fprintf(jfp, "D\n");
										break;
									case VOID_t:
										fprintf(jfp, "V\n");
										break;
									default:
										break;
								}
							}
						  | ID L_PAREN R_PAREN SEMICOLON
							{
								verifyFuncInvoke( $1, 0, symbolTable, scope );
								fprintf(jfp, "invokestatic output/%s()", $1);
								struct SymNode *func = lookupSymbol(symbolTable, $1, 0, __FALSE);
								struct PType *pType = func->type;
								switch(pType->type){
									case INTEGER_t:
										fprintf(jfp, "I\n");
										break;
									case BOOLEAN_t:
										fprintf(jfp, "Z\n");
										break;
									case FLOAT_t:
										fprintf(jfp, "F\n");
										break;
									case DOUBLE_t:
										fprintf(jfp, "D\n");
										break;
									case VOID_t:
										fprintf(jfp, "V\n");
										break;
									default:
										break;
								}
							}
						  ;

jump_statement : CONTINUE SEMICOLON
				{
					if( inloop <= 0){
						fprintf( stdout, "########## Error at Line#%d: continue can't appear outside of loop ##########\n", linenum ); semError = __TRUE;
					}
				}
			   | BREAK SEMICOLON 
				{
					if( inloop <= 0){
						fprintf( stdout, "########## Error at Line#%d: break can't appear outside of loop ##########\n", linenum ); semError = __TRUE;
					}
				}
			   | RETURN logical_expression SEMICOLON
				{
					verifyReturnStatement( $2, funcReturn );
					if (mainFlag == 1){
						fprintf(jfp, "return\n");
						mainFlag = 0;
					}
					else {
						switch(funcReturn->type){
							case BOOLEAN_t:
							case INTEGER_t:
								fprintf(jfp, "ireturn\n;");
								break;
							case FLOAT_t:
								fprintf(jfp, "freturn\n");
								break;
							case DOUBLE_t:
								fprintf(jfp, "dreturn\n");
								break;
							default:
								fprintf(jfp, "return\n");
								break;
						}
					}
					
				}
			   ;

variable_reference : ID
					{
						$$ = createExprSem( $1 );
					}
				   | variable_reference dimension
					{	
						increaseDim( $1, $2 );
						$$ = $1;
					}
				   ;

dimension : ML_BRACE arithmetic_expression MR_BRACE
			{
				$$ = verifyArrayIndex( $2 );
			}
		  ;
		  
logical_expression : logical_expression OR_OP logical_term
					{
						verifyAndOrOp( $1, OR_t, $3 );
						$$ = $1;
						fprintf(jfp, "ior\n");
					}
				   | logical_term { $$ = $1; }
				   ;

logical_term : logical_term AND_OP logical_factor
				{
					verifyAndOrOp( $1, AND_t, $3 );
					$$ = $1;
					fprintf(jfp, "iand\n");
				}
			 | logical_factor { $$ = $1; }
			 ;

logical_factor : NOT_OP logical_factor
				{
					verifyUnaryNOT( $2 );
					$$ = $2;
					fprintf(jfp, "iconst_1\nixor\n");
				}
			   | relation_expression { $$ = $1; }
			   ;

relation_expression : arithmetic_expression relation_operator arithmetic_expression
					{
						verifyRelOp( $1, $2, $3 );
						$$ = $1;

						condCnt++;
						labelCnt++;
						condStack[condCnt] = labelCnt;
						struct expr_sem *a = $1;
						struct expr_sem *b = $3;
						int typeA = a->pType->type;
						int typeB = b->pType->type;
						if ((typeA == FLOAT_t || typeA == FLOAT_t) || (typeB == FLOAT_t || typeB == DOUBLE_t)){
							fprintf(jfp, "fcmpl\n");
						}
						else
							fprintf(jfp, "isub\n");
						switch ($2){
							case LT_t:
								fprintf(jfp, "iflt Ltrue_%d\n", condStack[condCnt]);
								break;
							case LE_t:
								fprintf(jfp, "ifle Ltrue_%d\n", condStack[condCnt]);
								break;
							case EQ_t:
								fprintf(jfp, "ifeq Ltrue_%d\n", condStack[condCnt]);
								break;
							case GE_t:
								fprintf(jfp, "ifge Ltrue_%d\n", condStack[condCnt]);
								break;
							case GT_t:
								fprintf(jfp, "ifgt Ltrue_%d\n", condStack[condCnt]);
								break;
							case NE_t:
								fprintf(jfp, "ifne Ltrue_%d\n", condStack[condCnt]);
								break;
						}
						fprintf(jfp, "iconst_0\n");
						fprintf(jfp, "goto Lfalse_%d\n", condStack[condCnt]);
						fprintf(jfp, "Ltrue_%d:\n", condStack[condCnt]);
						fprintf(jfp, "iconst_1\n");
						fprintf(jfp, "Lfalse_%d:\n", condStack[condCnt]);
						condCnt--;
					}
					| arithmetic_expression { $$ = $1; }
					;

relation_operator : LT_OP { $$ = LT_t; }
				  | LE_OP { $$ = LE_t; }
				  | EQ_OP { $$ = EQ_t; }
				  | GE_OP { $$ = GE_t; }
				  | GT_OP { $$ = GT_t; }
				  | NE_OP { $$ = NE_t; }
				  ;

arithmetic_expression : arithmetic_expression add_op term
			{
				verifyArithmeticOp( $1, $2, $3 );
				$$ = $1;
				switch ($1->pType->type){
					case INTEGER_t:
						fprintf(jfp, "i");
						break;
					case FLOAT_t:
						fprintf(jfp, "f");
						break;
					case DOUBLE_t:
						fprintf(jfp, "d");
						break;
				}
				if ($2 == ADD_t){
					fprintf(jfp, "add\n");
				}
				else{
					fprintf(jfp, "sub\n");
				}
			}
                   | relation_expression { $$ = $1; }
		   | term { $$ = $1; }
		   ;

add_op	: ADD_OP { $$ = ADD_t; }
		| SUB_OP { $$ = SUB_t; }
		;
		   
term : term mul_op factor
		{
			if ($3->pType->type < $1->pType->type){
				switch ($1->pType->type){
					case FLOAT_t:
						fprintf(jfp, "i2f\n");
						break;
					case DOUBLE_t:
						fprintf(jfp, "i2d\n");
						break;
					default:
						break;		
				}
			}
			switch ($1->pType->type){
				case INTEGER_t:
					fprintf(jfp, "i");
					break;
				case FLOAT_t:
					fprintf(jfp, "f");
					break;
				case DOUBLE_t:
					fprintf(jfp, "d");
					break;
				default:
					break;
			}
			if( $2 == MOD_t ) {
				verifyModOp( $1, $3 );
				fprintf(jfp, "rem\n");
			}
			else {
				verifyArithmeticOp( $1, $2, $3 );
				if ($2 == DIV_t){
					fprintf(jfp, "div\n");
				}
				else{
					fprintf(jfp, "mul\n");
				}
			}
			$$ = $1;
		}
     | factor { $$ = $1; }
	 ;

mul_op 	: MUL_OP { $$ = MUL_t; }
		| DIV_OP { $$ = DIV_t; }
		| MOD_OP { $$ = MOD_t; }
		;
		
factor : variable_reference
		{
			verifyExistence( symbolTable, $1, scope, __FALSE );
			$$ = $1;
			$$->beginningOp = NONE_t;
			struct SymNode *curr = lookupSymbol(symbolTable, $1->varRef->id, scope, __FALSE);
			if (curr->scope == 0){
				if (curr->category == CONSTANT_t){
					if ($1->pType->type == INTEGER_t || $1->pType->type == BOOLEAN_t)
						fprintf(jfp, "ldc %d\n", curr->attribute->constVal->value);
					else
						fprintf(jfp, "ldc %f\n", curr->attribute->constVal->value);
				}
				else{
					switch($1->pType->type){
						case INTEGER_t:
							fprintf(jfp, "getstatic output/%s I\n", curr->name);
							break;
						case BOOLEAN_t:
							fprintf(jfp, "getstatic output/%s Z\n", curr->name);
							break;
						case DOUBLE_t:
							fprintf(jfp, "getstatic output/%s D\n", curr->name);
							break;
						case FLOAT_t:
							fprintf(jfp, "getstatic output/%s F\n", curr->name);
							break;
						default:
							break;
				}
				}
			}
			else {
				switch($1->pType->type){
					case INTEGER_t:
					case BOOLEAN_t:
						fprintf(jfp, "iload %d\n",curr->stackEntry);
						break;
					case DOUBLE_t:
						fprintf(jfp, "dload %d\n",curr->stackEntry);
						break;
					case FLOAT_t:
						fprintf(jfp, "fload %d\n",curr->stackEntry);
						break;
					default:
						break;
				}
			}
		}
	   | SUB_OP variable_reference
		{
			if( verifyExistence( symbolTable, $2, scope, __FALSE ) == __TRUE )
			verifyUnaryMinus( $2 );
			$$ = $2;
			$$->beginningOp = SUB_t;
			struct SymNode *curr = lookupSymbol(symbolTable, $2->varRef->id, scope, __FALSE);
			if (curr->scope == 0){
				switch($2->pType->type){
					case INTEGER_t:
						fprintf(jfp, "getstatic output/%s I\n", curr->name);
						fprintf(jfp, "ineg\n");
						break;
					case DOUBLE_t:
						fprintf(jfp, "getstatic output/%s D\n", curr->name);
						fprintf(jfp, "dneg\n");
						break;
					case FLOAT_t:
						fprintf(jfp, "getstatic output/%s F\n", curr->name);
						fprintf(jfp, "fneg\n");
						break;
					default:
						break;
				}
			}
			else {
				switch($2->pType->type){
					case INTEGER_t:
					case BOOLEAN_t:
						fprintf(jfp, "iload %d\n",curr->stackEntry);
						fprintf(jfp, "ineg\n");
						break;
					case DOUBLE_t:
						fprintf(jfp, "dload %d\n",curr->stackEntry);
						fprintf(jfp, "dneg\n");
						break;
					case FLOAT_t:
						fprintf(jfp, "fload %d\n",curr->stackEntry);
						fprintf(jfp, "fneg\n");
						break;
					default:
						break;
				}
			}
		}		
	   | L_PAREN logical_expression R_PAREN
		{
			$2->beginningOp = NONE_t;
			$$ = $2; 
		}
	   | SUB_OP L_PAREN logical_expression R_PAREN
		{
			verifyUnaryMinus( $3 );
			$$ = $3;
			$$->beginningOp = SUB_t;
		}
	   | ID L_PAREN logical_expression_list R_PAREN
		{
			$$ = verifyFuncInvoke( $1, $3, symbolTable, scope );
			$$->beginningOp = NONE_t;
			struct expr_sem *curr = $3;
			char paramType[10];
			int cnt = 0;
			while (curr != 0){
				char type;
				paramType[cnt] = '\0';
				switch (curr->pType->type){
					case INTEGER_t:
						paramType[cnt++] = 'I';
						break;
					case BOOLEAN_t:
						paramType[cnt++] = 'Z';
						break;
					case FLOAT_t:
						paramType[cnt++] = 'F';
						break;
					case DOUBLE_t:
						paramType[cnt++] = 'D';
						break;
					default:
						paramType[cnt++] = '\0';
						break;
				}
				curr = curr->next ;
			}
			paramType[cnt] = '\0';
			fprintf(jfp, "invokestatic output/%s(%s)", $1, paramType);
			struct SymNode *func = lookupSymbol(symbolTable, $1, 0, __FALSE);
			struct PType *pType = func->type;
			switch(pType->type){
				case INTEGER_t:
					fprintf(jfp, "I\n");
					break;
				case BOOLEAN_t:
					fprintf(jfp, "Z\n");
					break;
				case FLOAT_t:
					fprintf(jfp, "F\n");
					break;
				case DOUBLE_t:
					fprintf(jfp, "D\n");
					break;
				default:
					break;
			}
		}
	   | SUB_OP ID L_PAREN logical_expression_list R_PAREN
	    {
			$$ = verifyFuncInvoke( $2, $4, symbolTable, scope );
			$$->beginningOp = SUB_t;
		}
	   | ID L_PAREN R_PAREN
		{
			$$ = verifyFuncInvoke( $1, 0, symbolTable, scope );
			$$->beginningOp = NONE_t;
			fprintf(jfp, "invokestatic output/%s()", $1);
			struct SymNode *func = lookupSymbol(symbolTable, $1, 0, __FALSE);
			struct PType *pType = func->type;
			switch(pType->type){
				case INTEGER_t:
					fprintf(jfp, "I\n");
					break;
				case BOOLEAN_t:
					fprintf(jfp, "Z\n");
					break;
				case FLOAT_t:
					fprintf(jfp, "F\n");
					break;
				case DOUBLE_t:
					fprintf(jfp, "D\n");
					break;
				default:
					break;
			}
		}
	   | SUB_OP ID L_PAREN R_PAREN
		{
			$$ = verifyFuncInvoke( $2, 0, symbolTable, scope );
			$$->beginningOp = SUB_OP;
		}
	   | literal_const
	    {
			  $$ = (struct expr_sem *)malloc(sizeof(struct expr_sem));
			  $$->isDeref = __TRUE;
			  $$->varRef = 0;
			  $$->pType = createPType( $1->category );
			  $$->next = 0;
			  if( $1->hasMinus == __TRUE ) {
			  	$$->beginningOp = SUB_t;
			  }
			  else {
				$$->beginningOp = NONE_t;
			  }
			  switch ($$->pType->type){
			  	case INTEGER_t:
				  	fprintf(jfp, "ldc %d\n", $1->value.integerVal);
			  		break;
			  	case BOOLEAN_t:
			  		if ($1->value.booleanVal == 0){
			  			fprintf(jfp, "iconst_0\n");
			  		}
			  		else
			  			fprintf(jfp, "iconst_1\n");
			  		break;
			  	case DOUBLE_t:
				  	fprintf(jfp, "ldc %f\n", $1->value.doubleVal);
				  		break;
			  	case FLOAT_t:
				  	fprintf(jfp, "ldc %f\n", $1->value.floatVal);
			  		break;
			  	case STRING_t:
				  	fprintf(jfp, "ldc \"%s\"\n", $1->value.stringVal);
			  		break;
			  	default:
			  		break;
			  }
		}
	   ;

logical_expression_list : logical_expression_list COMMA logical_expression
						{
			  				struct expr_sem *exprPtr;
			  				for( exprPtr=$1 ; (exprPtr->next)!=0 ; exprPtr=(exprPtr->next) );
			  				exprPtr->next = $3;
			  				$$ = $1;
						}
						| logical_expression { $$ = $1; }
						;

		  


scalar_type : INT { $$ = createPType( INTEGER_t ); }
			| DOUBLE { $$ = createPType( DOUBLE_t ); }
			| STRING { $$ = createPType( STRING_t ); }
			| BOOL { $$ = createPType( BOOLEAN_t ); }
			| FLOAT { $$ = createPType( FLOAT_t ); }
			;
 
literal_const : INT_CONST
				{
					int tmp = $1;
					$$ = createConstAttr( INTEGER_t, &tmp );
				}
			  | SUB_OP INT_CONST
				{
					int tmp = -$2;
					$$ = createConstAttr( INTEGER_t, &tmp );
				}
			  | FLOAT_CONST
				{
					float tmp = $1;
					$$ = createConstAttr( FLOAT_t, &tmp );
				}
			  | SUB_OP FLOAT_CONST
			    {
					float tmp = -$2;
					$$ = createConstAttr( FLOAT_t, &tmp );
				}
			  | SCIENTIFIC
				{
					double tmp = $1;
					$$ = createConstAttr( DOUBLE_t, &tmp );
				}
			  | SUB_OP SCIENTIFIC
				{
					double tmp = -$2;
					$$ = createConstAttr( DOUBLE_t, &tmp );
				}
			  | STR_CONST
				{
					$$ = createConstAttr( STRING_t, $1 );
				}
			  | TRUE
				{
					SEMTYPE tmp = __TRUE;
					$$ = createConstAttr( BOOLEAN_t, &tmp );
				}
			  | FALSE
				{
					SEMTYPE tmp = __FALSE;
					$$ = createConstAttr( BOOLEAN_t, &tmp );
				}
			  ;
%%

int yyerror( char *msg )
{
    fprintf( stderr, "\n|--------------------------------------------------------------------------\n" );
	fprintf( stderr, "| Error found in Line #%d: %s\n", linenum, buf );
	fprintf( stderr, "|\n" );
	fprintf( stderr, "| Unmatched token: %s\n", yytext );
	fprintf( stderr, "|--------------------------------------------------------------------------\n" );
	exit(-1);
}


